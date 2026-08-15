// VGA text mode console: the scrollback, the VT100 sequences, the CP437 font
// and the cursor. Several consoles share one screen, so one only paints while
// it is the one being shown, see `activate`.

const std = @import("std");

const vga = @import("../vga/text.zig");
const themes = @import("themes.zig");
const cp437 = @import("cp437.zig");
const vt100 = @import("vt100.zig");

const TtyStruct = @import("../../tty/TtyStruct.zig");
const TtyDriver = @import("../../tty/TtyDriver.zig");

pub const width = vga.width;
pub const height = vga.height;

/// Lines of scrollback each console keeps.
pub const history_size: u32 = 1000;

comptime {
    if (history_size < height)
        @compileError("history_size must be greater than the terminal height");
}

/// The sixteen colours a VGA text cell can hold.
pub const Color = enum(u8) {
    black = 0,
    blue = 1,
    green = 2,
    cyan = 3,
    red = 4,
    magenta = 5,
    yellow = 6,
    white = 7,
    bright_black = 8,
    bright_blue = 9,
    bright_green = 10,
    bright_cyan = 11,
    bright_red = 12,
    bright_magenta = 13,
    bright_yellow = 14,
    bright_white = 15,
};

pub const Attribute = enum { reset, bold, dim, empty1, underline, blink, empty2, reverse, hidden };

pub const Pos = struct { line: u32 = 0, col: u32 = 0 };

/// Cursor and colours, as saved and restored by the VT100 sequences.
pub const State = struct {
    pos: Pos = .{},
    attributes: u32 = 0,
    current_color: u16 = 0,
};

const Self = @This();

/// Scrollback. The screen is a window onto it, `view` paints that window.
history_buffer: [history_size][width]u16 = undefined,

current_color: u16 = @intFromEnum(Color.white),

/// Set of Attribute, one bit each.
attributes: u32 = 0,

/// Where the next character goes, in scrollback coordinates.
pos: Pos = .{},

/// Lowest line written so far.
head_line: u32 = 0,

/// How far back the view is scrolled. Zero shows the bottom.
scroll_offset: u32 = 0,

write_state: enum { Normal, Escape } = .Normal,

escape_buffer: [10:0]u8 = [_:0]u8{0} ** 10,

theme: ?themes.Theme = themes.default,

/// Whether this console owns the screen right now.
active: bool = false,

/// The terminal this console is behind, for the sequences that answer back.
tty: *TtyStruct = undefined,

/// Attach this console to a terminal.
pub fn init(self: *Self, tty: *TtyStruct) void {
    self.tty = tty;
    tty.driver = &driver;
    tty.driver_data = @ptrCast(self);
    self.reset_color();
    self.clear();
}

fn of(tty: *TtyStruct) *Self {
    return @ptrCast(@alignCast(tty.driver_data.?));
}

/// The console behind a terminal, for what only a console can answer:
/// scrollback, palette, screen size. Null for a serial line.
pub fn from(tty: *TtyStruct) ?*Self {
    if (tty.driver != &driver) return null;
    return of(tty);
}

// Colours and themes

pub fn set_background_color(self: *Self, color: Color) void {
    self.current_color &= 0x0f;
    self.current_color |= @intFromEnum(color) << 4;
}

pub fn set_font_color(self: *Self, color: Color) void {
    self.current_color &= 0xf0;
    self.current_color |= @intFromEnum(color);
}

pub fn reset_color(self: *Self) void {
    if (self.theme) |t| {
        self.set_font_color(@enumFromInt(t.foreground_idx));
        self.set_background_color(@enumFromInt(t.background_idx));
    } else {
        self.set_font_color(Color.white);
        self.set_background_color(Color.black);
    }
}

pub fn blank_char(self: *Self) u16 {
    return ' ' |
        (@as(u16, if (self.theme) |t| t.background_idx else 0) << 12) |
        (@as(u16, (if (self.theme) |t| t.foreground_idx else 15)) << 8);
}

pub fn set_theme(self: *Self, new_theme: themes.Theme) void {
    self.theme = new_theme;
    self.refresh_theme();
}

/// The palette is one piece of hardware, so only the console being shown may
/// load its own.
pub fn refresh_theme(self: *Self) void {
    if (!self.active) return;
    if (self.theme) |t| vga.set_palette(t.palette);
}

// Scrollback

pub fn clear_line(self: *Self, line: u32) void {
    for (0..width) |i|
        self.history_buffer[line][i] = self.blank_char();
}

pub fn clear(self: *Self) void {
    for (0..history_size) |i| self.clear_line(@intCast(i));
}

/// Move the cursor, scrolling the scrollback along when it runs off the end.
pub fn move_cursor(self: *Self, line_offset: i32, col_offset: i32) void {
    var actual_line_offset = line_offset;
    if (col_offset < 0) {
        self.pos.col -|= @as(u32, @intCast(-col_offset));
    } else {
        self.pos.col += @as(u32, @intCast(col_offset));
    }
    actual_line_offset += @as(i32, @intCast(self.pos.col / width));
    self.pos.col %= width;

    if (actual_line_offset < 0) {
        if (@as(u32, @intCast(-actual_line_offset)) >= history_size) {
            self.pos.line = self.pos.line;
        } else {
            self.pos.line = self.pos.line + history_size - @as(u32, @intCast(-actual_line_offset));
        }
        self.pos.line %= history_size;
    } else {
        if (@as(u32, @intCast(actual_line_offset)) >= history_size) {
            self.pos.line = self.pos.line;
            self.head_line = self.pos.line;
            self.clear();
        } else {
            var pos_to_headline: u32 = 0;
            if (self.pos.line <= self.head_line) {
                pos_to_headline = self.head_line - self.pos.line;
            } else {
                pos_to_headline = history_size + (self.pos.line - self.head_line);
            }
            self.pos.line += @as(u32, @intCast(actual_line_offset));
            self.pos.line %= history_size;
            if (actual_line_offset > pos_to_headline) {
                for (0..(@as(u32, @intCast(actual_line_offset)) -| pos_to_headline)) |_| {
                    self.head_line += 1;
                    self.head_line %= history_size;
                    self.clear_line(self.head_line);
                }
            }
        }
    }
}

pub fn scroll(self: *Self, off: i32) void {
    if (off > 0) {
        self.scroll_offset += @intCast(off);
    } else {
        self.scroll_offset -|= @intCast(-off);
    }
    if (self.scroll_offset >= history_size - height)
        self.scroll_offset = history_size - height;
    self.view();
}

pub fn reset_scroll(self: *Self) void {
    if (self.scroll_offset != 0) {
        self.scroll_offset = 0;
        self.view();
    }
}

/// Cursor position relative to the screen rather than the scrollback.
pub fn get_state(self: *Self) State {
    return .{
        .pos = .{
            .line = @intCast(@mod(
                @as(i32, @intCast(self.pos.line)) -
                    (@as(i32, @intCast(self.head_line)) -
                        @as(i32, @intCast(self.scroll_offset)) -
                        @as(i32, @intCast(height - 1))),
                history_size,
            )),
            .col = self.pos.col,
        },
        .attributes = self.attributes,
        .current_color = self.current_color,
    };
}

pub fn set_state(self: *Self, new_state: State) void {
    self.pos = new_state.pos;
    self.attributes = new_state.attributes;
    self.current_color = new_state.current_color;
}

// Putting characters on the screen

/// Place one character at the cursor, applying the current colours and
/// attributes to the cell.
fn put_char_to_buffer(self: *Self, c: u8) void {
    var char: u16 = c;
    char |= self.current_color << 8;
    if (self.attributes & (@as(u16, 1) << @intFromEnum(Attribute.bold)) != 0) {
        char |= @as(u16, 0b00001000) << 8;
    }
    if (self.attributes & (@as(u16, 1) << @intFromEnum(Attribute.blink)) != 0) {
        char |= @as(u16, 0b10000000) << 8;
    }
    if (self.attributes & (@as(u16, 1) << @intFromEnum(Attribute.reverse)) != 0) {
        const swap = char;
        char &= 0x00ff;
        char |= (swap & 0x0f00) << 4;
        char |= (swap & 0xf000) >> 4;
    }
    if (self.attributes & (@as(u16, 1) << @intFromEnum(Attribute.hidden)) != 0) {
        char = (char & 0xf0ff) | ((char & 0xf000) >> 4);
    }
    self.history_buffer[self.pos.line][self.pos.col] = char;
    self.move_cursor(0, 1);
}

/// Characters that move the cursor rather than mark the screen.
fn process_whitespaces(self: *Self, c: u8) void {
    switch (c) {
        '\n' => {
            // ONLRET makes a newline return to the left margin as well.
            if (self.tty.config.c_oflag.ONLRET) {
                self.move_cursor(1, -@as(i32, @intCast(self.pos.col)));
            } else {
                self.move_cursor(1, 0);
            }
        },
        '\t' => {
            // TODO: REAL tabs
            self.move_cursor(0, @as(i32, @intCast(4 -| self.pos.col % 4)));
        },
        '\r' => {
            self.move_cursor(0, -@as(i32, @intCast(self.pos.col)));
        },
        8 => { // backspace
            self.move_cursor(0, -1);
        },
        11 => { // vertical tab
            self.move_cursor(1, 0);
        },
        12 => { // form feed
            // TODO?
        },
        ' '...'~', 0x80...0xfe => {
            self.put_char_to_buffer(c);
        },
        else => {}, // unknown characters are discarded
    }
}

/// One character, through the escape sequence state machine.
fn putchar(self: *Self, c: u8) void {
    switch (self.write_state) {
        .Escape => if (std.mem.len(@as([*:0]u8, &self.escape_buffer)) < self.escape_buffer.len - 1) {
            var buffer_save: @TypeOf(self.escape_buffer) = undefined;
            self.escape_buffer[std.mem.len(@as([*:0]u8, &self.escape_buffer))] = c;
            self.write_state = .Normal;
            @memcpy(&buffer_save, &self.escape_buffer);
            @memset(&self.escape_buffer, 0);
            if (!(vt100.handle_escape(self, &buffer_save) catch true)) {
                @memcpy(&self.escape_buffer, &buffer_save);
                self.write_state = .Escape;
            }
        } else {
            // The sequence outgrew the buffer, so it was not one.
            var tmp: @TypeOf(self.escape_buffer) = undefined;
            @memcpy(&tmp, &self.escape_buffer);
            @memset(&self.escape_buffer, 0);
            self.write_state = .Normal;
            for (std.mem.sliceTo(&tmp, 0)) |held| self.putchar(held);
            self.putchar(c);
        },
        .Normal => {
            if (c == 0x1b) {
                self.write_state = .Escape;
            } else {
                self.process_whitespaces(c);
            }
        },
    }
}

/// Paint the visible window of the scrollback onto the screen.
pub fn view(self: *Self) void {
    if (!self.active) return;
    for (0..height) |l| {
        for (0..width) |c| {
            const view_line = (history_size + history_size + self.head_line + 1 -|
                height -| self.scroll_offset) % history_size;
            const buffer_line = (view_line + l) % history_size;
            vga.put_char(l, c, if (((buffer_line < self.head_line or (buffer_line == self.head_line))) or
                (self.head_line < view_line and buffer_line >= view_line))
                switch (self.history_buffer[buffer_line][c]) {
                    0 => self.blank_char(),
                    else => |char| char,
                }
            else
                self.blank_char());
        }
    }
    self.put_cursor();
}

/// Show the hardware cursor when the writing position is on screen.
fn put_cursor(self: *Self) void {
    const offset = (self.head_line + history_size - self.scroll_offset) % history_size;
    const is_visible: bool = if (offset < height)
        self.pos.line > ((offset + history_size - height) % history_size) or self.pos.line <= offset
    else
        self.pos.line > (offset - height) and self.pos.line <= offset;
    if (is_visible) {
        vga.enable_cursor();

        const pos = self.get_state().pos;
        vga.set_cursor_pos(@intCast(pos.col), @intCast(pos.line)); // todo: int casts
    } else {
        vga.disable_cursor();
    }
}

// Driver

/// The hardware speaks CP437, so UTF-8 is folded into it here rather than
/// anywhere a serial line would be affected.
fn driver_write(tty: *TtyStruct, data: []const u8) usize {
    const self = of(tty);
    var iter = cp437.Utf8ToCp437Iterator{ .bytes = data };
    while (iter.next()) |c| self.putchar(c);
    return data.len;
}

fn driver_put_char(tty: *TtyStruct, c: u8) void {
    of(tty).putchar(c);
}

fn driver_flush(tty: *TtyStruct) void {
    of(tty).view();
}

fn driver_activate(tty: *TtyStruct, active: bool) void {
    const self = of(tty);
    self.active = active;
    if (!active) return;
    self.refresh_theme();
    self.view();
}

pub const driver = TtyDriver{
    .write = &driver_write,
    .put_char = &driver_put_char,
    .flush = &driver_flush,
    .activate = &driver_activate,
};
