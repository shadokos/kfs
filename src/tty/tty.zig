const ft = @import("../ft/ft.zig");
const Writer = ft.io.Writer;
const fmt = ft.fmt;
const vt100 = @import("vt100.zig").vt100;

/// The colors available for the console
pub const Color = enum(u8) {
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

pub const Attribute = enum {
	reset,
	bold,
	dim,
	empty1,
	underline,
	blink,
	empty2,
	reverse,
	hidden
};

/// screen width
pub const width = 80;
/// screen height
pub const height = 25;

/// ft.Writer implementation for TtyN
fn TtyWriter(comptime history_size: u32) type { return Writer(*TtyN(history_size), TtyN(history_size).write_error, TtyN(history_size).write); }

/// address of the mmio vga buffer
var mmio_buffer: [*]u16 = @ptrFromInt(0xB8000);

/// TtyN is a generic struct that represent a vt100-like terminal, it can be written and can
/// be shown on the screen with the view function, TtyN include a scrollable
/// history and various functions to control the view displacement.
/// The template parameter to TtyN is the size of the (statically allocated) history
pub fn TtyN(comptime history_size: u32) type {
    return struct {
        /// history buffer
        history_buffer: [history_size][width]u16 = undefined,

        /// current color
        current_color: u16 = 0,

        /// attributes ('or' of 1 << Attribute)
        attributes: u32 = 0,

        /// current position in the history buffer
        pos: struct { line: u32, col: u32 } = .{ .line = 0, .col = 0 },

		/// the lower line writen
        head_line: u32 = 0,

        /// current offset for view (0 mean bottom)
        scroll_offset: u32 = 0,

        /// writer for the buffer
        writer: TtyWriter(history_size) = undefined,

		/// current writing state (either Normal or escape)
		write_state : enum {Normal, Escape} = .Normal,
        // escape_mode: bool = false,

		/// buffer for escape sequences
        escape_buffer: [10:0]u8 = [_:0]u8{0} ** 10,

        pub const write_error = error{};

        const Self = @This();

        /// clear line line in the history buffer
        pub fn clear_line(self: *Self, line: u32) void {
            for (0..width) |i|
                self.history_buffer[line][i] = ' ';
        }

		/// move the curser of line_offset vertically and col_offset horizontally
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
                	var truc : u32 = 0;
                	if (self.pos.line <= self.head_line) {
                		truc = self.head_line - self.pos.line;
                	} else {
                		truc = history_size - (self.head_line - self.pos.line);
                	}
					self.pos.line += @as(u32, @intCast(actual_line_offset));
					self.pos.line %= history_size;
					if (actual_line_offset > truc)
					{
						for (0..(@as(u32, @intCast(actual_line_offset))-|truc)) |_|
						{
							self.head_line += 1;
							self.head_line %= history_size;
							self.clear_line(self.head_line);
						}
					}
                }
            }
        }



        /// write the character c in the buffer
        pub fn putchar(self: *Self, c: u8) void {
            switch (self.write_state) {
            	.Escape => if (ft.mem.len(@as([*:0]u8, &self.escape_buffer)) < self.escape_buffer.len - 1) {
						self.escape_buffer[ft.mem.len(@as([*:0]u8, &self.escape_buffer))] = c;
						if (vt100(history_size).handle_escape(self, &self.escape_buffer) catch true)
						{
							@memset(&self.escape_buffer, 0);
							self.write_state = .Normal;
						}
					} else {
						self.write_state = .Normal;
	            	},
            	.Normal => switch (c) {
					0x1b => {
						self.write_state = .Escape;
					},
					'\n' => {
						self.move_cursor(1, -@as(i32, @intCast(self.pos.col)));
					},
					'\t' => {
						self.move_cursor(0, @as(i32, @intCast(4 -| self.pos.col % 4))); // todo: REAL tabs
					},
					'\r' => {
						self.move_cursor(0, -@as(i32, @intCast(self.pos.col)));
					},
					8 => { // backspace
						self.move_cursor(0, -1);
					},
					11 => { // vertical tab
						self.move_cursor(-1, 0);
					},
					12 => { // form feed
						// todo
						// self.move_cursor(height, -@as(i32, @intCast(self.pos.col)));
					},
					' '...'~' => {
						var char : u16 = c;
						char |= self.current_color << 8;
						// if (self.attributes & (@as(u16, 1) << @intFromEnum(Attribute.blink)) != 0) {
						// 	char |= 1 << 15;
						// }
						if (self.attributes & (@as(u16, 1) << @intFromEnum(Attribute.dim)) == 0) {
							char |= 1 << 3 << 8;
						}
						if (self.attributes & (@as(u16, 1) << @intFromEnum(Attribute.reverse)) != 0) {
							var swap = char;
							char &= 0x00ff;
							char |= (swap & 0x0f00) << 4;
							char |= (swap & 0xf000) >> 4;
						}
						if (self.attributes & (@as(u16, 1) << @intFromEnum(Attribute.hidden)) != 0) {
							char = (char & 0xf0ff) | ((char & 0xf000) >> 4);
						}
						self.history_buffer[self.pos.line][self.pos.col] = char;
						self.move_cursor(0, 1);
					},
					else => {}, // todo
				}
            }
        }

        /// write the string s to the buffer and return the number of bites writen, suitable for use with ft.io.Writer
        pub fn write(self: *Self, s: []const u8) Self.write_error!usize {
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
            self.writer = TtyWriter(history_size){ .context = self };
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
                self.scroll_offset -|= @intCast(-off);
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
                    const view_line = (history_size + history_size + self.head_line + 1 -| height -| self.scroll_offset) % history_size;
                    const buffer_line = (view_line + l) % history_size;
                    mmio_buffer[l * width + c] = if (((buffer_line < self.head_line or (buffer_line == self.head_line))) or (self.head_line < view_line and buffer_line >= view_line))
                        self.history_buffer[buffer_line][c]
                    else
                        ' ';
                }
            }
        }
    };
}

/// Tty is a specialisation of TtyN with an history size of 1000
pub const Tty = TtyN(1000);
