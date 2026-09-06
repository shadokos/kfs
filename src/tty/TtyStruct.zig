// One terminal, with nothing in it that knows what the hardware is. Anything
// that has to touch hardware goes through `driver`, see TtyDriver.zig.

const std = @import("std");

const termios = @import("termios.zig");
const TtyDriver = @import("TtyDriver.zig");
const InputBuffer = @import("InputBuffer.zig");
const Pid = @import("../task/task.zig").TaskDescriptor.Pid;
const n_tty = @import("ldisc/n_tty.zig");
const wait_queue = @import("../task/wait_queue.zig");

const Self = @This();

/// Index of this terminal in the array it belongs to.
index: u8 = 0,

/// Hardware behind this terminal. The no-op driver swallows output, which is
/// what an unattached terminal should do rather than fault.
driver: *const TtyDriver = &noop_driver,

/// The driver's own state, reached with `@ptrCast` by the driver itself.
driver_data: ?*anyopaque = null,

/// Current termios configuration.
config: termios.termios = .{},

/// What the discipline has produced and read() has not taken. POSIX 11.1.5
/// calls this the input queue.
input_buffer: InputBuffer = .{},

/// Raised by a driver interrupt, cleared by the input task, which then asks the
/// driver for what arrived.
events: bool = false,

/// Readers waiting for the discipline to publish something.
read_queue: wait_queue.WaitQueue(.{ .predicate = input_ready }) = .{},

/// Raised when the VTIME timer fires, cleared when a read starts waiting again.
read_timed_out: bool = false,

/// The line dropped, POSIX 11.1.10. Reads report end of input and writes are
/// refused until the last close.
hung_up: bool = false,

/// Descriptors open on this terminal. The last to go takes the line down,
/// POSIX 11.1.11.
open_count: usize = 0,

/// Output suspended by the STOP character or by tcflow, POSIX 11.2.2. A writer
/// waits rather than losing what it had to say.
output_stopped: bool = false,

/// Writers held back while output is suspended.
output_queue: wait_queue.WaitQueue(.{ .predicate = output_ready }) = .{},

/// Process group the control characters of this terminal signal, POSIX 11.1.2.
/// Null until something claims the terminal, and nothing is signalled then.
foreground_pgid: ?Pid = null,

/// Session this terminal controls, POSIX 11.1.3. At most one, hence a single
/// pointer.
session: ?*@import("../task/session.zig") = null,

// Input and reading, which the line discipline owns

/// Feed bytes arriving from the hardware through the line discipline.
pub fn input(self: *Self, s: []const u8) void {
    n_tty.receive(self, s);
}

/// A waiting reader is woken by input arriving or by VTIME running out, and
/// has to tell the two apart itself.
fn input_ready(_: *void, data: ?*void) bool {
    const self: *Self = @ptrCast(@alignCast(data.?));
    return self.read_timed_out or n_tty.has_input(self);
}

fn output_ready(_: *void, data: ?*void) bool {
    const self: *Self = @ptrCast(@alignCast(data.?));
    return !self.output_stopped;
}

/// Suspend or resume output, POSIX 11.2.2. Resuming wakes whoever was waiting.
pub fn set_output_stopped(self: *Self, stopped: bool) void {
    self.output_stopped = stopped;
    if (!stopped) self.output_queue.try_unblock();
}

/// Wait until output is allowed again. Interruptible: a job frozen by a STOP
/// character must still be killable.
pub fn wait_for_output(self: *Self) error{EINTR}!void {
    while (self.output_stopped)
        self.output_queue.block(
            @import("../task/scheduler.zig").get_current_task(),
            @ptrCast(self),
        ) catch return error.EINTR;
}

/// Read from the terminal, suitable for std.io.Reader.
pub fn read(self: *Self, s: []u8) ReadError!usize {
    return n_tty.read(self, s);
}

// Writing

pub const WriteError = error{};

/// A read cut short by a signal has to say so: zero already means end of input.
pub const ReadError = error{EINTR};

pub const Writer = std.io.GenericWriter(*Self, WriteError, write);
pub const Reader = std.io.GenericReader(*Self, ReadError, read);

/// Send bytes out through output processing, without pushing them to the
/// hardware yet. Only CR and LF are rewritten, so the runs between them go to
/// the driver whole and a multibyte sequence is never cut in half.
pub fn output(self: *Self, s: []const u8) void {
    if (!self.config.c_oflag.OPOST) {
        _ = self.driver.write(self, s);
        return;
    }

    var start: usize = 0;
    for (s, 0..) |c, i| {
        const replacement: []const u8 = if (self.config.c_oflag.ONLCR and c == '\n')
            "\r\n"
        else if (self.config.c_oflag.OCRNL and c == '\r')
            "\n"
        else
            continue;

        if (i != start) _ = self.driver.write(self, s[start..i]);
        _ = self.driver.write(self, replacement);
        start = i + 1;
    }
    if (start != s.len) _ = self.driver.write(self, s[start..]);
}

/// Write to the terminal, suitable for std.io.Writer.
pub fn write(self: *Self, s: []const u8) WriteError!usize {
    self.output(s);
    self.driver_flush();
    return s.len;
}

pub fn writer(self: *Self) Writer {
    return Writer{ .context = self };
}

pub fn reader(self: *Self) Reader {
    return Reader{ .context = self };
}

// Reaching the hardware

/// Wait for the hardware to have sent everything, for tcdrain.
pub fn drain(self: *Self) void {
    if (self.driver.drain) |f| f(self);
}

/// Drop what the hardware has not sent, for tcflush.
pub fn flush_output(self: *Self) void {
    if (self.driver.flush_output) |f| f(self);
}

pub fn driver_flush(self: *Self) void {
    if (self.driver.flush) |flush| flush(self);
}

/// Hand the terminal to a process group, and give back the one it replaces so
/// that a caller can put it back afterwards.
pub fn set_foreground_pgid(self: *Self, pgid: ?Pid) ?Pid {
    const previous = self.foreground_pgid;
    self.foreground_pgid = pgid;
    return previous;
}

/// The line dropped, POSIX 11.1.10. SIGHUP goes to the session leader and not
/// to the foreground group: it is the session that loses its terminal. CLOCAL
/// means there is no carrier to lose.
pub fn hangup(self: *Self) void {
    if (self.config.c_cflag.CLOCAL) return;

    self.hung_up = true;

    if (self.session) |session| {
        if (@import("../task/task_set.zig").get_task_descriptor(session.sid)) |leader| {
            leader.send_signal(.{
                .si_signo = .{ .valid = .SIGHUP },
                .si_code = .SI_KERNEL,
                .si_pid = 0,
            });
        }
    }

    // A read that returns nothing, a write that is refused.
    self.read_queue.try_unblock();
    self.set_output_stopped(false);
}

pub fn opened(self: *Self) void {
    self.open_count += 1;
}

/// POSIX 11.1.11: the last close sends what was written, throws away what was
/// typed and not read, and drops the line if HUPCL says so.
pub fn closed(self: *Self) void {
    if (self.open_count > 0) self.open_count -= 1;
    if (self.open_count != 0) return;

    self.drain();
    self.input_buffer.clear();

    if (self.config.c_cflag.HUPCL) {
        if (self.driver.hangup) |f| f(self);
        self.hung_up = false;
    }
}

/// Tell the driver whether this terminal is the one being shown.
pub fn set_active(self: *Self, active: bool) void {
    if (self.driver.activate) |activate| activate(self, active);
}

/// Apply new settings and let the driver reprogram itself.
pub fn set_termios(self: *Self, new: termios.termios) void {
    const old = self.config;
    self.config = new;
    if (self.driver.set_termios) |set| set(self, old);
}

// A terminal with nothing behind it

fn noop_write(_: *Self, data: []const u8) usize {
    return data.len;
}

const noop_driver = TtyDriver{ .write = &noop_write };
