// VGA text mode console driver.
// Implements the TtyDriver interface for VGA consoles with scrollback,
// VT100 escape sequences, themes, and CP437 encoding.
const std = @import("std");
const vga = @import("../../drivers/vga/text.zig");
const themes = @import("themes.zig");
const cp437 = @import("cp437.zig");
const TtyStruct = @import("../../device/tty/tty_struct.zig");
const TtyDriver = @import("../../device/tty/tty_driver.zig");
const tty_mod = @import("../../device/tty/tty.zig");

pub const width = vga.width;
pub const height = vga.height;

const history_size: u32 = 1000;

const Self = @This();

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

const Pos = struct { line: u32 = 0, col: u32 = 0 };

const State = struct {
    pos: Pos = .{},
    attributes: u32 = 0,
    current_color: u16 = 0,
};

history_buffer: [history_size][width]u16 = undefined,

current_color: u16 = @intFromEnum(Color.white),

attributes: u32 = 0,

pos: Pos = .{},

head_line: u32 = 0,

scroll_offset: u32 = 0,

write_state: enum { Normal, Escape } = .Normal,

escape_buffer: [10:0]u8 = [_:0]u8{0} ** 10,

theme: ?themes.Theme = themes.default,

// Back-pointer to the owning TtyStruct.
tty: *TtyStruct = undefined,

pub fn console_init(self: *Self, tty_s: *TtyStruct) void {
    self.tty = tty_s;
    tty_s.driver = &vt_driver;
    tty_s.driver_data = @ptrCast(self);
    self.reset_color();
    self.refresh_theme();
    self.view();
}

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

pub fn set_theme(self: *Self, _theme: themes.Theme) void {
    self.theme = _theme;
    self.refresh_theme();
}

pub fn refresh_theme(self: *Self) void {
    if (self.theme) |t| {
        vga.set_palette(t.palette);
    }
}

pub fn clear_line(self: *Self, line: u32) void {
    for (0..width) |i|
        self.history_buffer[line][i] = self.blank_char();
}

pub fn clear(self: *Self) void {
    for (0..history_size) |i| {
        self.clear_line(i);
    }
}

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

fn process_whitespaces(self: *Self, c: u8) void {
    switch (c) {
        '\n' => {
            if (self.tty.config.c_oflag.ONLRET) {
                self.move_cursor(1, -@as(i32, @intCast(self.pos.col)));
            } else {
                self.move_cursor(1, 0);
            }
        },
        '\t' => {
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
        12 => {}, // form feed (TODO)
        ' '...'~', 0x80...0xfe => {
            self.put_char_to_buffer(c);
        },
        else => {}, // unknown characters are discarded
    }
}

fn handle_escape_output(self: *Self, c: u8) void {
    switch (self.write_state) {
        .Escape => if (std.mem.len(@as([*:0]u8, &self.escape_buffer)) < self.escape_buffer.len - 1) {
            var buffer_save: @TypeOf(self.escape_buffer) = undefined;
            self.escape_buffer[std.mem.len(@as([*:0]u8, &self.escape_buffer))] = c;
            self.write_state = .Normal;
            @memcpy(&buffer_save, &self.escape_buffer);
            @memset(&self.escape_buffer, 0);
            if (!(self.handle_escape(&buffer_save) catch true)) {
                @memcpy(&self.escape_buffer, &buffer_save);
                self.write_state = .Escape;
            }
        } else {
            var tmp: @TypeOf(self.escape_buffer) = undefined;
            @memcpy(&tmp, &self.escape_buffer);
            @memset(&self.escape_buffer, 0);
            self.write_state = .Normal;
            for (tmp[0..]) |b| {
                if (b == 0) break;
                self.process_whitespaces(b);
            }
            self.process_whitespaces(c);
        },
        .Normal => {
            if (self.tty.config.c_oflag.ONLCR and c == '\n') {
                self.process_whitespaces('\r');
                self.process_whitespaces('\n');
            } else if (self.tty.config.c_oflag.OCRNL and c == '\r') {
                self.process_whitespaces('\n');
            } else if (c == 0x1b) {
                self.write_state = .Escape;
            } else {
                self.process_whitespaces(c);
            }
        },
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

fn put_cursor(self: *Self) void {
    const offset = (self.head_line + history_size - self.scroll_offset) % history_size;
    const is_visible: bool = if (offset < height)
        self.pos.line > ((offset + history_size - height) % history_size) or self.pos.line <= offset
    else
        self.pos.line > (offset - height) and self.pos.line <= offset;
    if (is_visible) {
        vga.enable_cursor();
        const state = self.get_state();
        vga.set_cursor_pos(@intCast(state.pos.col), @intCast(state.pos.line));
    } else {
        vga.disable_cursor();
    }
}

/// Render the visible portion of the history buffer to VGA.
pub fn view(self: *Self) void {
    // Only render if this console is the active one.
    if (&consoles[tty_mod.current_tty] != self)
        return;
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

// VT100 escape handler

fn handle_move(self: *Self, buffer: [:0]const u8) void {
    const len = std.mem.indexOfSentinel(u8, 0, buffer);
    const n: i32 = std.fmt.parseInt(i32, buffer[1 .. len - 1], 10) catch 1;
    switch (buffer[len - 1]) {
        'A' => self.move_cursor(-n, 0),
        'B' => self.move_cursor(n, 0),
        'C' => self.move_cursor(0, n),
        'D' => self.move_cursor(0, -n),
        else => {},
    }
}

fn handle_set_attribute(self: *Self, buffer: [:0]const u8) void {
    const len = std.mem.indexOfSentinel(u8, 0, buffer);
    const n: u32 = std.fmt.parseInt(u32, buffer[1 .. len - 1], 10) catch 0;
    switch (n) {
        @intFromEnum(Attribute.reset) => {
            self.attributes = 0;
            self.reset_color();
        },
        @intFromEnum(Attribute.bold)...@intFromEnum(Attribute.hidden) => {
            self.attributes |= @as(u16, 1) << @intCast(n);
        },
        30...37 => {
            self.set_font_color(switch (n) {
                30 => Color.black,
                31 => Color.red,
                32 => Color.green,
                33 => Color.yellow,
                34 => Color.blue,
                35 => Color.magenta,
                36 => Color.cyan,
                37 => Color.white,
                else => Color.white,
            });
        },
        40...47 => {
            self.set_background_color(switch (n) {
                40 => Color.black,
                41 => Color.red,
                42 => Color.green,
                43 => Color.yellow,
                44 => Color.blue,
                45 => Color.magenta,
                46 => Color.cyan,
                47 => Color.white,
                else => Color.black,
            });
        },
        else => {},
    }
}

fn handle_save(self: *Self, buffer: [:0]const u8) void {
    const saved_state = struct {
        var value: ?State = null;
    };
    switch (buffer[0]) {
        '7' => saved_state.value = self.get_state(),
        '8' => if (saved_state.value) |value| self.set_state(value),
        else => unreachable,
    }
}

fn handle_clearline(self: *Self, buffer: [:0]const u8) void {
    const len = std.mem.indexOfSentinel(u8, 0, buffer);
    const n: i32 = std.fmt.parseInt(i32, buffer[1 .. len - 1], 10) catch 0;
    switch (n) {
        0 => {
            for (self.pos.col..width) |i|
                self.history_buffer[self.pos.line][i] = self.blank_char();
        },
        1 => {
            for (0..self.pos.col + 1) |i|
                self.history_buffer[self.pos.line][i] = self.blank_char();
        },
        2 => self.clear_line(self.pos.line),
        else => {},
    }
}

fn handle_clearscreen(self: *Self, buffer: [:0]const u8) void {
    const len = std.mem.indexOfSentinel(u8, 0, buffer);
    const n: i32 = std.fmt.parseInt(i32, buffer[1 .. len - 1], 10) catch 0;
    const screen_bottom = (self.head_line + history_size - self.scroll_offset) % history_size;
    var screen_top = (screen_bottom + history_size - height + 1) % history_size;

    switch (n) {
        0 => {
            screen_top = self.pos.line;
            while (screen_top != screen_bottom) {
                self.clear_line(screen_top);
                screen_top += 1;
                screen_top %= history_size;
            }
            self.clear_line(screen_top);
        },
        1 => {
            while (screen_top != self.pos.line) {
                self.clear_line(screen_top);
                screen_top += 1;
                screen_top %= history_size;
            }
            self.clear_line(screen_top);
        },
        2 => {
            while (screen_top != screen_bottom) {
                self.clear_line(screen_top);
                screen_top += 1;
                screen_top %= history_size;
            }
            self.clear_line(screen_top);
        },
        else => {},
    }
}

fn handle_goto(self: *Self, buffer: [:0]const u8) void {
    const semicolon_pos = std.mem.indexOfScalarPos(u8, buffer, 1, ';') orelse 0;
    var v: u32 = 0;
    var h: u32 = 0;
    if (semicolon_pos != 0) {
        const len = std.mem.indexOfSentinel(u8, 0, buffer);
        v = std.fmt.parseInt(u32, buffer[1..semicolon_pos], 10) catch 0;
        h = std.fmt.parseInt(u32, buffer[semicolon_pos + 1 .. len - 1], 10) catch 0;
    }
    const off_v: i32 = -@as(i32, @intCast(self.pos.line)) +
        @mod(@as(i32, @intCast(self.head_line)) -
            @as(i32, @intCast(self.scroll_offset)) -
            @as(i32, @intCast(height - 1)) +
            @as(i32, @intCast(v)), history_size);
    const off_h: i32 = -@as(i32, @intCast(self.pos.col)) + @as(i32, @intCast(h));
    self.move_cursor(off_v, off_h);
}

fn handle_get_pos(self: *Self, _: [:0]const u8) void {
    var buffer: [100]u8 = [1]u8{0} ** 100;
    const slice = std.fmt.bufPrint(&buffer, "\x1b{d};{d}R", .{
        self.get_state().pos.line,
        self.get_state().pos.col,
    }) catch return;

    self.tty.input(slice);
}

fn handle_nothing(_: *Self, _: [:0]const u8) void {}

fn compare_prefix(prefix: [:0]const u8, buffer: [:0]const u8) bool {
    var i: u32 = 0;
    var j: u32 = 0;

    while (prefix[i] != 0 and buffer[j] != 0) {
        if (prefix[i] == '^') {
            if (!std.ascii.isDigit(buffer[j]))
                return false;
            while (buffer[j] != 0 and std.ascii.isDigit(buffer[j])) {
                j += 1;
            }
        } else if (prefix[i] != buffer[j]) {
            return false;
        } else {
            j += 1;
        }
        i += 1;
    }
    return prefix[i] == 0;
}

fn handle_escape(self: *Self, buffer: [:0]const u8) error{InvalidEscape}!bool {
    const Handler = *const fn (*Self, [:0]const u8) void;
    const map = [_]struct { prefix: [:0]const u8, f: Handler }{
        .{ .prefix = "[20h", .f = &handle_nothing },
        .{ .prefix = "[?^h", .f = &handle_nothing },
        .{ .prefix = "[20l", .f = &handle_nothing },
        .{ .prefix = "[?^l", .f = &handle_nothing },
        .{ .prefix = "=", .f = &handle_nothing },
        .{ .prefix = ">", .f = &handle_nothing },
        .{ .prefix = "(A", .f = &handle_nothing },
        .{ .prefix = ")A", .f = &handle_nothing },
        .{ .prefix = "(B", .f = &handle_nothing },
        .{ .prefix = ")B", .f = &handle_nothing },
        .{ .prefix = "(^", .f = &handle_nothing },
        .{ .prefix = ")^", .f = &handle_nothing },
        .{ .prefix = "N", .f = &handle_nothing },
        .{ .prefix = "O", .f = &handle_nothing },
        .{ .prefix = "[m", .f = &handle_set_attribute },
        .{ .prefix = "[^m", .f = &handle_set_attribute },
        .{ .prefix = "[^;^r", .f = &handle_nothing },
        .{ .prefix = "[A", .f = &handle_move },
        .{ .prefix = "[^A", .f = &handle_move },
        .{ .prefix = "[B", .f = &handle_move },
        .{ .prefix = "[^B", .f = &handle_move },
        .{ .prefix = "[C", .f = &handle_move },
        .{ .prefix = "[^C", .f = &handle_move },
        .{ .prefix = "[D", .f = &handle_move },
        .{ .prefix = "[^D", .f = &handle_move },
        .{ .prefix = "[H", .f = &handle_goto },
        .{ .prefix = "[;H", .f = &handle_goto },
        .{ .prefix = "[^;^H", .f = &handle_goto },
        .{ .prefix = "[f", .f = &handle_goto },
        .{ .prefix = "[;f", .f = &handle_goto },
        .{ .prefix = "[^;^f", .f = &handle_goto },
        .{ .prefix = "D", .f = &handle_nothing },
        .{ .prefix = "M", .f = &handle_nothing },
        .{ .prefix = "E", .f = &handle_nothing },
        .{ .prefix = "7", .f = &handle_save },
        .{ .prefix = "8", .f = &handle_save },
        .{ .prefix = "H", .f = &handle_nothing },
        .{ .prefix = "[g", .f = &handle_nothing },
        .{ .prefix = "[0g", .f = &handle_nothing },
        .{ .prefix = "[3g", .f = &handle_nothing },
        .{ .prefix = "#3", .f = &handle_nothing },
        .{ .prefix = "#4", .f = &handle_nothing },
        .{ .prefix = "#5", .f = &handle_nothing },
        .{ .prefix = "#6", .f = &handle_nothing },
        .{ .prefix = "[K", .f = &handle_clearline },
        .{ .prefix = "[^K", .f = &handle_clearline },
        .{ .prefix = "[J", .f = &handle_clearscreen },
        .{ .prefix = "[^J", .f = &handle_clearscreen },
        .{ .prefix = "5n", .f = &handle_nothing },
        .{ .prefix = "0n", .f = &handle_nothing },
        .{ .prefix = "3n", .f = &handle_nothing },
        .{ .prefix = "6n", .f = &handle_get_pos },
        .{ .prefix = "^;^R", .f = &handle_nothing },
        .{ .prefix = "[c", .f = &handle_nothing },
        .{ .prefix = "[0c", .f = &handle_nothing },
        .{ .prefix = "?1;^c", .f = &handle_nothing },
        .{ .prefix = "c", .f = &handle_nothing },
        .{ .prefix = "#8", .f = &handle_nothing },
        .{ .prefix = "[2;1y", .f = &handle_nothing },
        .{ .prefix = "[2;2y", .f = &handle_nothing },
        .{ .prefix = "[2;9y", .f = &handle_nothing },
        .{ .prefix = "[2;10y", .f = &handle_nothing },
        .{ .prefix = "[0q", .f = &handle_nothing },
        .{ .prefix = "[1q", .f = &handle_nothing },
        .{ .prefix = "[2q", .f = &handle_nothing },
        .{ .prefix = "[3q", .f = &handle_nothing },
        .{ .prefix = "[4q", .f = &handle_nothing },
    };
    for (map) |e| {
        if (compare_prefix(e.prefix, buffer)) {
            e.f(self, buffer);
            return true;
        }
    }
    return false;
}

// TtyDriver interface

/// Write output through CP437 encoding and VT100 handling.
fn vt_write(tty_s: *TtyStruct, data: []const u8) usize {
    const self = get_console(tty_s);
    var iter = cp437.Utf8ToCp437Iterator{ .bytes = data };

    while (iter.next()) |cp437_char| {
        if (tty_s.config.c_oflag.OPOST) {
            self.handle_escape_output(cp437_char);
        } else {
            self.process_whitespaces(cp437_char);
        }
    }
    self.view();
    return data.len;
}

fn vt_put_char(tty_s: *TtyStruct, c: u8) void {
    const self = get_console(tty_s);
    if (tty_s.config.c_oflag.OPOST) {
        self.handle_escape_output(c);
    } else {
        self.process_whitespaces(c);
    }
    self.view();
}

fn vt_flush(tty_s: *TtyStruct) void {
    const self = get_console(tty_s);
    self.view();
    self.refresh_theme();
}

fn get_console(tty_s: *TtyStruct) *Self {
    return @ptrCast(@alignCast(tty_s.driver_data));
}

fn vt_receive(_: *TtyStruct) void {
    @import("../input/keyboard/keyboard.zig").kb_read();
}

pub const vt_driver = TtyDriver{
    .write = &vt_write,
    .put_char = &vt_put_char,
    .flush = &vt_flush,
    .receive = &vt_receive,
};

// Global console instances

pub var consoles: [tty_mod.num_consoles]Self = [1]Self{Self{}} ** tty_mod.num_consoles;
pub fn init() void {
    tty_mod.init(&vt_driver);
    for (consoles[0..], 0..) |*con, i| {
        con.console_init(&tty_mod.tty_array[i]);
    }
}
