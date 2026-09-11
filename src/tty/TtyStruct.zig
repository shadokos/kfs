// One terminal, with nothing in it that knows what the hardware is. Anything
// that has to touch hardware goes through `driver`, see TtyDriver.zig.

const std = @import("std");

const termios = @import("termios.zig");
const TtyDriver = @import("TtyDriver.zig");
const InputBuffer = @import("InputBuffer.zig");
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

pub fn driver_flush(self: *Self) void {
    if (self.driver.flush) |flush| flush(self);
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
