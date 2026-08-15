// One terminal, with nothing in it that knows what the hardware is. Anything
// that has to touch hardware goes through `driver`, see TtyDriver.zig.

const std = @import("std");

const termios = @import("termios.zig");
const TtyDriver = @import("TtyDriver.zig");

const MAX_INPUT: usize = 4096; // must be a power of 2

comptime {
    if (@popCount(MAX_INPUT) != 1)
        @compileError("MAX_INPUT must be a power of 2");
}

const input_buffer_pos_t = std.meta.Int(.unsigned, std.math.log2(MAX_INPUT));

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

/// Input ring buffer.
input_buffer: [MAX_INPUT]u8 = undefined,

/// End of the input area, where new input is written.
read_head: input_buffer_pos_t = 0,

/// Start of the unread part, where read() takes from.
read_tail: input_buffer_pos_t = 0,

/// In canonical mode, start of the line being edited.
current_line_begin: input_buffer_pos_t = 0,

/// End of the processed area.
current_line_end: input_buffer_pos_t = 0,

/// First byte the line discipline has not looked at yet.
unprocessed_begin: input_buffer_pos_t = 0,

// Input

/// Feed bytes arriving from the hardware through the line discipline.
pub fn input(self: *Self, s: []const u8) void {
    for (s) |c| self.input_char(c);
    self.local_processing();
    // Echo went to the driver a byte at a time; nothing has told it to show
    // what it accumulated yet.
    self.driver_flush();
}

/// Queue one byte, after the c_iflag translations.
fn input_char(self: *Self, c: u8) void {
    if (self.input_processing(c)) |p| if (self.read_head +% 1 != self.read_tail) {
        self.input_buffer[self.read_head] = p;
        self.read_head +%= 1;
    };
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
fn is_echoctl(self: Self, c: u8) bool {
    return c & 0b11100000 == 0 and
        c != '\t' and
        c != '\n' and
        c != self.config.c_cc[@intFromEnum(termios.cc_index.VSTART)] and
        c != self.config.c_cc[@intFromEnum(termios.cc_index.VSTOP)];
}

/// Take one character back off the line being edited.
fn erase_char(self: *Self) void {
    if (self.config.c_lflag.ECHO and self.config.c_lflag.ECHOE) {
        self.driver_write("\x08 \x08");
        self.current_line_end -%= 1;
        if (self.config.c_lflag.ECHOCTL and self.is_echoctl(self.input_buffer[self.current_line_end]))
            self.driver_write("\x08 \x08");
    } else {
        self.current_line_end -%= 1;
    }
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

/// POSIX local processing, the canonical and non-canonical modes of c_lflag.
fn local_processing(self: *Self) void {
    if (self.config.c_lflag.ICANON) {
        while (self.unprocessed_begin != self.read_head) {
            const c: u8 = self.input_buffer[self.unprocessed_begin];
            self.unprocessed_begin +%= 1;

            if (self.is_end_of_line(c)) {
                if (c != self.config.c_cc[@intFromEnum(termios.cc_index.VEOF)]) {
                    self.echo(c);
                }
                self.input_buffer[self.current_line_end] = c;
                self.current_line_end +%= 1;
                self.current_line_begin = self.current_line_end;
            } else if (c == self.config.c_cc[@intFromEnum(termios.cc_index.VERASE)]) {
                if (self.current_line_end != self.current_line_begin) {
                    self.erase_char();
                }
            } else if (c == self.config.c_cc[@intFromEnum(termios.cc_index.VKILL)]) {
                while (self.current_line_end != self.current_line_begin) {
                    self.erase_char();
                }
                // todo ECHOK
            } else {
                self.input_buffer[self.current_line_end] = c;
                self.current_line_end +%= 1;
                self.echo(c);
            }
        }
        self.read_head = self.current_line_end;
        self.unprocessed_begin = self.current_line_end;
    } else {
        while (self.current_line_end != self.read_head) {
            if (self.config.c_lflag.ECHO or
                (self.input_buffer[self.current_line_end] == '\n' and
                    self.config.c_lflag.ECHONL))
                self.driver_putchar(self.input_buffer[self.current_line_end]);
            self.current_line_end +%= 1;
        }
    }
}

// Reading and writing

pub const WriteError = error{};
pub const ReadError = error{};

pub const Writer = std.io.GenericWriter(*Self, WriteError, write);
pub const Reader = std.io.GenericReader(*Self, ReadError, read);

/// Read from the terminal, suitable for std.io.Reader.
///
/// In canonical mode a read is satisfied by a complete line; otherwise by any
/// byte the line discipline has published. VMIN and VTIME are not honoured yet.
pub fn read(self: *Self, s: []u8) ReadError!usize {
    var count: usize = 0;
    for (s) |*c| {
        while (self.read_tail == self.current_line_begin and self.read_head +% 1 != self.read_tail) {
            @import("../cpu.zig").halt();
            @import("../drivers/input/keyboard/keyboard.zig").kb_read();
        }

        c.* = self.input_buffer[self.read_tail];
        if (self.read_tail == self.current_line_begin)
            self.current_line_begin +%= 1;
        self.read_tail +%= 1;
        count += 1;
        if (self.config.c_lflag.ICANON and self.is_end_of_line(c.*)) {
            if (c.* == self.config.c_cc[@intFromEnum(termios.cc_index.VEOF)])
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
