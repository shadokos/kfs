// Core TTY structure.
//
// Hardware-agnostic part of the TTY subsystem. Holds termios config,
// line discipline state, input ring buffer, and a pointer to the
// hardware driver backend (TtyDriver).
const std = @import("std");
const termios = @import("termios.zig");
const TtyDriver = @import("tty_driver.zig");

const MAX_INPUT: usize = 4096;

const input_buffer_pos_t = std.meta.Int(.unsigned, std.math.log2(MAX_INPUT));

const Self = @This();

index: u8 = 0,

// No-op driver by default, replaced when a real driver is attached.
driver: *const TtyDriver = &noop_driver,

// Opaque pointer for driver-private data.
driver_data: *anyopaque = @ptrFromInt(@as(usize, 0xDEAD)),

/// Current termios configuration.
config: termios.termios = .{},

/// Input ring buffer.
input_buffer: [MAX_INPUT]u8 = undefined,

/// Points to the end of the input area (where new input is written).
read_head: input_buffer_pos_t = 0,

/// Points to the beginning of the unread part (where read() consumes from).
read_tail: input_buffer_pos_t = 0,

/// In canonical mode, points to the start of the current active line.
current_line_begin: input_buffer_pos_t = 0,

/// Points to the end of the processed area.
current_line_end: input_buffer_pos_t = 0,

/// Points to the first unprocessed byte in the input buffer.
unprocessed_begin: input_buffer_pos_t = 0,

/// Process input through the line discipline.
pub fn input(self: *Self, s: []const u8) void {
    for (s) |c| self.input_char(c);
    self.local_processing();
}

/// Queue one raw byte with POSIX input flag processing.
fn input_char(self: *Self, c: u8) void {
    if (self.input_processing(c)) |p| {
        if (self.read_head +% 1 != self.read_tail) {
            self.input_buffer[self.read_head] = p;
            self.read_head +%= 1;
        }
    }
}

// POSIX input processing: IGNCR, ICRNL, INLCR.
fn input_processing(self: *Self, c: u8) ?u8 {
    if (self.config.c_iflag.IGNCR and c == '\r') return null;
    if (self.config.c_iflag.ICRNL and c == '\r') return '\n';
    if (self.config.c_iflag.INLCR and c == '\n') return '\r';
    return c;
}

fn is_end_of_line(self: *Self, c: u8) bool {
    return c == '\n' or
        c == self.config.c_cc[@intFromEnum(termios.cc_index.VEOL)] or
        c == self.config.c_cc[@intFromEnum(termios.cc_index.VEOF)];
}

fn is_echoctl(self: *Self, c: u8) bool {
    return c & 0b11100000 == 0 and
        c != '\t' and
        c != '\n' and
        c != self.config.c_cc[@intFromEnum(termios.cc_index.VSTART)] and
        c != self.config.c_cc[@intFromEnum(termios.cc_index.VSTOP)];
}

/// Erase one character (canonical mode backspace).
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

/// Echo a character, respecting ECHO / ECHONL / ECHOCTL.
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

/// Canonical/raw mode local processing.
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

// Output processing: OPOST, ONLCR, OCRNL, ONLRET.
pub fn output_processing(self: *Self, c: u8) void {
    if (self.config.c_oflag.OPOST) {
        if (self.config.c_oflag.ONLCR and c == '\n') {
            self.driver_putchar('\r');
            self.driver_putchar('\n');
        } else if (self.config.c_oflag.OCRNL and c == '\r') {
            self.driver_putchar('\n');
        } else {
            self.driver_putchar(c);
        }
    } else {
        self.driver_putchar(c);
    }
}

pub const WriteError = error{};
pub const ReadError = error{};

pub const Writer = std.io.GenericWriter(*Self, WriteError, write);
pub const Reader = std.io.GenericReader(*Self, ReadError, read);

/// Read from the TTY. In canonical mode, blocks until a full line
/// is available. In raw mode, blocks until at least one byte is ready.
pub fn read(self: *Self, s: []u8) ReadError!usize {
    var count: usize = 0;
    for (s) |*c| {
        // Block until data is available.
        // Canonical: wait for a complete line.
        // Raw: wait for any processed byte.
        while (true) {
            const has_data = if (self.config.c_lflag.ICANON)
                self.read_tail != self.current_line_begin
            else
                self.read_tail != self.current_line_end;
            if (has_data) break;
            @import("../../cpu.zig").halt();
            if (self.driver.receive) |receive_fn| {
                receive_fn(self);
            }
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

/// Write to the TTY output, going through the driver's write path.
pub fn write(self: *Self, s: []const u8) WriteError!usize {
    _ = self.driver.write(self, s);
    return s.len;
}

/// Get a std.io.GenericWriter for this TTY.
pub fn writer(self: *Self) Writer {
    return Writer{ .context = self };
}

/// Get a std.io.GenericReader for this TTY.
pub fn reader(self: *Self) Reader {
    return Reader{ .context = self };
}

/// Write a string through the driver (used by line discipline for echo).
fn driver_write(self: *Self, data: []const u8) void {
    _ = self.driver.write(self, data);
}

/// Put a single character through the driver.
fn driver_putchar(self: *Self, c: u8) void {
    if (self.driver.put_char) |put_char_fn| {
        put_char_fn(self, c);
    } else {
        _ = self.driver.write(self, &[1]u8{c});
    }
}

/// Flush the driver output buffer.
pub fn driver_flush(self: *Self) void {
    if (self.driver.flush) |flush_fn| {
        flush_fn(self);
    }
}

/// Apply new termios and notify the driver.
pub fn set_termios(self: *Self, new: termios.termios) void {
    const old = self.config;
    self.config = new;
    if (self.driver.set_termios) |set_fn| {
        set_fn(self, old);
    }
}

// No-op default driver

fn noop_write(_: *Self, data: []const u8) usize {
    return data.len;
}

const noop_driver = TtyDriver{
    .write = &noop_write,
};
