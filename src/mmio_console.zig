const std = @import("std");
const Writer = @import("std").io.Writer;
const fmt = @import("std").fmt;

/// The colors available for the console
pub const Color = enum(u4) {
    black = 0,
    blue = 1,
    green = 2,
    cyan = 3,
    red = 4,
    magenta = 5,
    brown = 6,
    light_grey = 7,
    dark_grey = 8,
    light_blue = 9,
    light_green = 10,
    light_cyan = 11,
    light_red = 12,
    light_magenta = 13,
    light_brown = 14,
    white = 15,
};

/// screen width
const width = 80;
/// screen height
const height = 25;

const BufferWriter = Writer(*Buffer, std.os.WriteError, Buffer.write);

/// address of the mmio vga buffer
var mmio_buffer: [*]u16 = @ptrFromInt(0xB8000);

/// BufferN is a generic struct that represent a screen, it can be written and can
/// be shown on the screen with the view function, BufferN include a scrollable
/// history and various functions to control the view displacement.
/// The template parameter to BufferN is the size of the (statically allocated) history
pub fn BufferN(comptime history_size: u32) type {
    return struct {
        /// history buffer
        history_buffer: [history_size][width]u16 = undefined,

        /// current color
        current_color: u16 = 0,

        /// current position in the history buffer
        pos: struct { line: u32, col: u32 } = .{ .line = 0, .col = 0 },

        /// current offset for view (0 mean bottom)
        scroll_offset: u32 = 0,

        /// writer for the buffer
        writer: BufferWriter = undefined,

        const Self = @This();

        /// clear line line in the history buffer
        fn clear_line(self: *Self, line: u32) void {
            for (0..width) |i|
                self.history_buffer[line][i] = ' ';
        }

        /// write the character c in the buffer
        pub fn putchar(self: *Self, c: u8) void {
            if (self.pos.col == 0)
                self.clear_line(self.pos.line);
            switch (c) {
                '\n' => {
                    self.pos.col = 0;
                    self.pos.line += 1;
                },
                '\t' => {
                    self.pos.col += 4;
                },
                '\r' => {
                    self.pos.col = 0;
                },
                8 => { // backspace
                    self.pos.col -= 1;
                },
                11 => { // vertical tab
                    self.pos.line += 1;
                    self.clear_line(self.pos.line);
                },
                12 => { // form feed
                    for (0..height) |_| {
                        self.pos.line += 1;
                        self.pos.line %= history_size;
                        self.clear_line(self.pos.line);
                    }
                    self.pos.col = 0;
                },
                ' '...'~' => {
                    self.history_buffer[self.pos.line][self.pos.col] = (self.current_color << 8) | c;
                    self.pos.col += 1;
                },
                else => {},
            }
            if (self.pos.col >= width) {
                self.pos.line += 1;
                self.pos.col = 0;
            }
            if (self.pos.line >= history_size)
                self.pos.line = 0;
        }

        /// write the string s to the buffer and return the number of bites writen, suitable for use with std.io.Writer
        pub fn write(self: *Self, s: []const u8) std.os.WriteError!usize {
            var ret: usize = 0;
            for (s) |c| {
                self.putchar(c);
                ret += 1;
            }
            return ret;
        }

        /// write the string s to the buffer
        pub fn putstr(self: *Self, s: []const u8) void {
            _ = self.write(s) catch 0;
        }

        /// initialize the writer field of the buffer
        pub fn init_writer(self: *Self) void {
            self.writer = BufferWriter{ .context = self };
        }

        /// write a formatted string to the buffer
        pub fn printf(self: *Self, comptime format: []const u8, args: anytype) void {
            fmt.format(self.writer, format, args) catch unreachable;
        }

        /// clear the buffer
        pub fn clear(self: *Self) void {
            for (0..history_size) |i| {
                self.clear_line(i);
            }
        }

        /// set the background color for the next chars
        pub fn set_background_color(self: *Self, color: Color) void {
            self.current_color &= 0x00ff;
            self.current_color |= @intFromEnum(color) << 4;
        }

        /// set the font color for the next chars
        pub fn set_font_color(self: *Self, color: Color) void {
            self.current_color &= 0xff00;
            self.current_color |= @intFromEnum(color);
        }

        /// move the view to the bottom of the buffer
        pub fn set_view_bottom(self: *Self) void {
            self.scroll_offset = 0;
        }

        /// move the view to the top of the buffer
        pub fn set_view_top(self: *Self) void {
            self.scroll_offset = history_size - height;
        }

        pub fn scroll(self: *Self, off: i32) void {
            if (off > 0) {
                self.scroll_offset += @intCast(off);
            } else {
                self.scroll_offset -= @intCast(off);
            }
            if (self.scroll_offset >= history_size)
                self.set_view_top();
        }

        /// move the view one page up
        pub fn page_up(self: *Self) void {
            self.scroll(height);
        }

        /// move the view one page down
        pub fn page_down(self: *Self) void {
            self.scroll(-height);
        }

        /// print the buffer to the vga buffer
        pub fn view(self: Self) void {
            for (0..height) |l| {
                for (0..width) |c| {
                    const view_line = (history_size + history_size + self.pos.line + 1 -| height -| self.scroll_offset) % history_size;
                    const buffer_line = (view_line + l) % history_size;
                    mmio_buffer[l * width + c] = if (((buffer_line < self.pos.line or (buffer_line == self.pos.line and c < self.pos.col))) or (self.pos.line < view_line and buffer_line >= view_line))
                        self.history_buffer[buffer_line][c]
                    else
                        ' ';
                }
            }
        }
    };
}

/// Buffer is a specialisation of BufferN with an history size of 1000
pub const Buffer = BufferN(1000);
