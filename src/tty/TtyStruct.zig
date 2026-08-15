// One terminal, with nothing in it that knows what the hardware is. Anything
// that has to touch hardware goes through `driver`, see TtyDriver.zig.

const std = @import("std");

const termios = @import("termios.zig");
const TtyDriver = @import("TtyDriver.zig");
const InputBuffer = @import("InputBuffer.zig");

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

/// What the line discipline has produced and read() has not taken.
input_buffer: InputBuffer = .{},

// Input

/// Feed bytes arriving from the hardware through the line discipline.
pub fn input(self: *Self, s: []const u8) void {
    for (s) |c| self.input_char(c);
    // Echo went to the driver a byte at a time; nothing has told it to show
    // what it accumulated yet.
    self.driver_flush();
}

/// One byte, all the way through the line discipline.
fn input_char(self: *Self, raw: u8) void {
    const c = self.input_processing(raw) orelse return;

    if (!self.config.c_lflag.ICANON) {
        // Nothing is being edited, so a byte is readable as soon as it lands.
        self.input_buffer.push(c);
        self.input_buffer.commit();
        self.echo(c);
        return;
    }

    if (self.is_end_of_line(c)) {
        // EOF ends the line without appearing on the screen. It is still kept,
        // so that read() can tell a line ended by EOF from one ended by a
        // newline, see `read`.
        if (c != self.config.c_cc[@intFromEnum(termios.cc_index.VEOF)]) self.echo(c);
        self.input_buffer.push(c);
        self.input_buffer.commit();
    } else if (c == self.config.c_cc[@intFromEnum(termios.cc_index.VERASE)]) {
        self.erase_char();
    } else if (c == self.config.c_cc[@intFromEnum(termios.cc_index.VKILL)]) {
        while (self.input_buffer.head != self.input_buffer.canon_head) self.erase_char();
        // todo ECHOK
    } else {
        self.input_buffer.push(c);
        self.echo(c);
    }
}

/// POSIX input processing: IGNCR, ICRNL, INLCR.
fn input_processing(self: *Self, c: u8) ?u8 {
    return if (self.config.c_iflag.IGNCR and c == '\r') null else if (self.config.c_iflag.ICRNL and
        c == '\r') '\n' else if (self.config.c_iflag.INLCR and
        c == '\n') '\r' else c;
}

fn is_end_of_line(self: *Self, c: u8) bool {
    return c == '\n' or
        c == self.config.c_cc[@intFromEnum(termios.cc_index.VEOL)] or
        c == self.config.c_cc[@intFromEnum(termios.cc_index.VEOF)];
}

/// Whether ECHOCTL should show this byte as ^X rather than send it through.
fn is_echoctl(self: *const Self, c: u8) bool {
    return c & 0b11100000 == 0 and
        c != '\t' and
        c != '\n' and
        c != self.config.c_cc[@intFromEnum(termios.cc_index.VSTART)] and
        c != self.config.c_cc[@intFromEnum(termios.cc_index.VSTOP)];
}

/// Take one character back off the line being edited, and unprint it.
///
/// A character ECHOCTL showed as ^X took two columns, so it takes two to rub
/// out. Doing nothing when the line is empty is what stops erase at the start
/// of a line, POSIX 11.1.6.
fn erase_char(self: *Self) void {
    const erased = self.input_buffer.erase() orelse return;
    if (!(self.config.c_lflag.ECHO and self.config.c_lflag.ECHOE)) return;

    self.driver_write("\x08 \x08");
    if (self.config.c_lflag.ECHOCTL and self.is_echoctl(erased))
        self.driver_write("\x08 \x08");
}

fn echo(self: *Self, c: u8) void {
    if (self.config.c_lflag.ECHO or (c == '\n' and self.config.c_lflag.ECHONL)) {
        if (self.config.c_lflag.ECHOCTL and self.is_echoctl(c)) {
            self.driver_putchar('^');
            self.driver_putchar(c | 0b01000000);
        } else {
            self.driver_putchar(c);
        }
    }
}

// Reading and writing

pub const WriteError = error{};
pub const ReadError = error{};

pub const Writer = std.io.GenericWriter(*Self, WriteError, write);
pub const Reader = std.io.GenericReader(*Self, ReadError, read);

/// Whether a read can be satisfied right now. A canonical read may only reach
/// a completed line, POSIX 11.1.6.
fn has_input(self: *const Self) bool {
    return if (self.config.c_lflag.ICANON)
        self.input_buffer.canon_count() != 0
    else
        self.input_buffer.count() != 0;
}

/// Read from the terminal, suitable for std.io.Reader.
///
/// VMIN and VTIME are not honoured yet, so a read returns on a complete line in
/// canonical mode and on the first byte otherwise.
pub fn read(self: *Self, s: []u8) ReadError!usize {
    var count: usize = 0;
    for (s) |*c| {
        while (!self.has_input()) {
            @import("../cpu.zig").halt();
            @import("../drivers/input/keyboard/keyboard.zig").kb_read();
        }

        const byte = self.input_buffer.pop().?;
        c.* = byte;
        count += 1;

        if (self.config.c_lflag.ICANON and self.is_end_of_line(byte)) {
            // EOF ended the line, so it is not part of it. A line holding only
            // EOF gives a read of zero, which is how a terminal reports the end
            // of its input.
            if (byte == self.config.c_cc[@intFromEnum(termios.cc_index.VEOF)])
                count -= 1;
            break;
        }
    }
    return count;
}

/// Write to the terminal, suitable for std.io.Writer.
///
/// Output processing only ever rewrites CR and LF, so the untouched runs
/// between them are handed to the driver whole. A driver that decodes multibyte
/// input therefore never sees a sequence cut in half, which chunking by a fixed
/// buffer size would not guarantee.
pub fn write(self: *Self, s: []const u8) WriteError!usize {
    if (!self.config.c_oflag.OPOST) {
        _ = self.driver.write(self, s);
        self.driver_flush();
        return s.len;
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

/// Write straight to the driver, skipping output processing. Echo uses this:
/// what the line discipline emits is already in its final form.
fn driver_write(self: *Self, data: []const u8) void {
    _ = self.driver.write(self, data);
}

fn driver_putchar(self: *Self, c: u8) void {
    if (self.driver.put_char) |put_char| {
        put_char(self, c);
    } else {
        _ = self.driver.write(self, &[1]u8{c});
    }
}

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
