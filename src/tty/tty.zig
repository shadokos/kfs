const ft = @import("../ft/ft.zig");
const fmt = ft.fmt;
const vt100 = @import("vt100.zig").vt100;
const termios = @import("termios.zig");
const cc_t = termios.cc_t;
const keyboard = @import("keyboard.zig");

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

const MAX_INPUT = 4096;

/// screen width
pub const width = 80;
/// screen height
pub const height = 25;

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
        current_color: u16 = @intFromEnum(Color.white),

        /// attributes ('or' of 1 << Attribute)
        attributes: u32 = 0,

        /// current position in the history buffer
        pos: Self.Pos = .{},

		/// the lower line writen
        head_line: u32 = 0,

        /// current offset for view (0 mean bottom)
        scroll_offset: u32 = 0,

		/// current writing state (either Normal or escape)
		write_state : enum {Normal, Escape} = .Normal,
        // escape_mode: bool = false,

		/// buffer for escape sequences
        escape_buffer: [10:0]u8 = [_:0]u8{0} ** 10,

        // current_line: [MAX_CANON]u8 = undefined,

        read_buffer: [MAX_INPUT]u8 = undefined,

        read_head: usize = 0,

        read_tail: usize = 0,

        delimited_line_end: usize = 0,
        current_line_end: usize = 0,

        unprocessed_begin: usize = 0,

        config: termios.termios = .{},
        
        pub const Writer = ft.io.Writer(*Self, Self.WriteError, Self.write);

        pub const WriteError = error{};
        pub const ReadError = error{};

        pub const Pos = struct {
        	line: u32 = 0,
        	col: u32 = 0
        };

        pub const State = struct {
        	pos: Pos = .{},
        	attributes: u32 = 0,
        	current_color: u16 = 0,
        };

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

        pub fn input(self: *Self, s: [] const u8) void {
        	for (s) |c| {
        		self.read_buffer[self.read_head] = c;
        		self.read_head += 1;
        		self.read_head %= self.read_buffer.len;
        	}
			if (self.read_tail == self.delimited_line_end)
				self.process_input();
        }

        fn is_end_of_line(self: *Self, c: u8) bool {
        	return c == '\n' or c == self.config.c_cc[@intFromEnum(termios.cc_index.VEOL)] or c == self.config.c_cc[@intFromEnum(termios.cc_index.VEOF)];
        }

        fn process_input(self: *Self) void {
	        if (self.config.c_lflag & termios.ICANON != 0) {
	        	if (self.delimited_line_end != self.read_tail)
	        		return;
	        	while (self.unprocessed_begin != self.read_head) : ({self.current_line_end %= self.read_buffer.len; self.unprocessed_begin %= self.read_buffer.len;})
	        	{
	        		if (self.is_end_of_line(self.read_buffer[self.unprocessed_begin])) {
	        			if (self.read_buffer[self.unprocessed_begin] != self.config.c_cc[@intFromEnum(termios.cc_index.VEOF)])
						{
							self.putchar(self.read_buffer[self.unprocessed_begin]);
	        			}
						self.read_buffer[self.current_line_end] = self.read_buffer[self.unprocessed_begin];
						self.unprocessed_begin += 1;
						self.unprocessed_begin %= self.read_buffer.len;
	        			self.delimited_line_end = self.current_line_end;
	        			continue;
	        		} else if (self.read_buffer[self.unprocessed_begin] == self.config.c_cc[@intFromEnum(termios.cc_index.VERASE)]) {
	        			if (self.current_line_end != self.delimited_line_end)
						{
							if (self.config.c_lflag & termios.ECHO != 0 and self.config.c_lflag & termios.ECHOE != 0)
							{
								_ = self.write("\x08 \x08") catch {};
							}
							self.current_line_end -= 1;
						}
	        		} else if (self.read_buffer[self.unprocessed_begin] == self.config.c_cc[@intFromEnum(termios.cc_index.VKILL)]) {
						if (self.config.c_lflag & termios.ECHO != 0) // todo ECHOK
	        				_ = self.write("\r\x1b[K") catch {}; // todo
	        			self.current_line_end = self.delimited_line_end;
	        		} else {
						if (self.config.c_lflag & termios.ECHO != 0 or (self.read_buffer[self.unprocessed_begin] == '\n' and self.config.c_lflag & termios.ECHONL != 0))
							self.putchar(self.read_buffer[self.unprocessed_begin]);
						self.read_buffer[self.current_line_end] = self.read_buffer[self.unprocessed_begin];
						self.current_line_end += 1;
	        		}
					self.unprocessed_begin += 1;
	        	}
	        	self.read_head = self.current_line_end;
	        } else {
	        	while (self.current_line_end != self.read_head) : (self.current_line_end %= self.read_buffer.len)
	        	{
					if (self.config.c_lflag & termios.ECHO != 0 or (self.read_buffer[self.current_line_end] == '\n' and self.config.c_lflag & termios.ECHONL != 0))
						self.putchar(self.read_buffer[self.current_line_end]);
	        		self.current_line_end += 1;
	        	}
	        }
        }

        fn read_buffer_size(self: *Self) usize {
        	return self.read_buffer.len - self.available_buffer_space();
        }


        fn put_char_to_buffer(self: *Self, c: u8) void {
			var char : u16 = c;
			char |= self.current_color << 8;
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
        }

        fn process_whitespaces(self: *Self, c: u8) void {
            	switch (c) {
					'\n' => {
						if (self.config.c_oflag & termios.ONLRET != 0)
							{self.move_cursor(1, -@as(i32, @intCast(self.pos.col)));}
						else
							{self.move_cursor(1, 0);}
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
						self.put_char_to_buffer(c);
					},
					else => {}, // todo
				}
        }

        /// write the character c in the buffer after mapping
        fn output_processing(self: *Self, c: u8) void {
        	if (self.config.c_oflag & termios.OPOST != 0)
        	{
           		switch (self.write_state) {
					.Escape => if (ft.mem.len(@as([*:0]u8, &self.escape_buffer)) < self.escape_buffer.len - 1) {
						var buffer_save: @TypeOf(self.escape_buffer) = undefined;
						self.escape_buffer[ft.mem.len(@as([*:0]u8, &self.escape_buffer))] = c;
						self.write_state = .Normal;
						@memcpy(&buffer_save, &self.escape_buffer);
						@memset(&self.escape_buffer, 0);
						if (!(vt100(history_size).handle_escape(self, &buffer_save) catch true)) {
							@memcpy(&self.escape_buffer, &buffer_save);
							self.write_state = .Escape;
						}
					},
					.Normal => {
						if (self.config.c_oflag & termios.ONLCR != 0 and c == '\n')
						{
							self.process_whitespaces('\r');
							self.process_whitespaces('\n');
						}
						else if (self.config.c_oflag & termios.OCRNL != 0 and c == '\r')
						{
							self.process_whitespaces('\n');
						}
						else if (self.config.c_oflag & termios.OCRNL != 0 and c == '\r' and self.pos.col == 0)
						{}
						else if (c == 0x1b) {
							self.write_state = .Escape;
						} else {
							self.process_whitespaces(c);
						}
					},
				}
			} else {
				self.process_whitespaces(c);
			}
        }
        
        /// write the character c to the terminal
        pub fn putchar(self: *Self, c: u8) void {
			self.output_processing(c);
        }

        pub fn read(self: *Self, s: [] u8) Self.ReadError!usize {
        	// todo time/min
        	var count : usize = 0;
        	for (s) |*c| {

        		if (self.read_tail == self.delimited_line_end)
        		{
        			keyboard.send_to_tty();
        			self.process_input();
        			if (self.read_tail == self.read_head)
        				break;
        		}

        		if (self.config.c_lflag & termios.ICANON != 0 and self.read_tail == self.delimited_line_end)
        			break;
        		c.* = self.read_buffer[self.read_tail];
        		self.read_tail += 1;
        		self.read_tail %= self.read_buffer.len;
        		count += 1;
	        	if (self.config.c_lflag & termios.ICANON != 0 and self.is_end_of_line(self.read_buffer[self.read_tail]))
	        	{
        			if (c.* == self.config.c_cc[@intFromEnum(termios.cc_index.VEOF)])
        				count -= 1;
					// self.read_tail = self.delimited_line_end;
	        		break;
	        	}
        	}
        	return count;
        }

        /// write the string s to the buffer and return the number of bites writen, suitable for use with ft.io.Writer
        pub fn write(self: *Self, s: []const u8) Self.WriteError!usize {
            var ret: usize = 0;
            for (s) |c| {
                self.putchar(c);
                ret += 1;
            }
            return ret;
        }

        pub fn get_state(self: *Self) Self.State {
			return .{
				.pos = .{
					.line = @intCast(@mod(@as(i32,@intCast(self.pos.line)) - (@as(i32,@intCast(self.head_line)) - @as(i32,@intCast(self.scroll_offset)) - @as(i32,@intCast(height - 1))), history_size)),
					.col = self.pos.col
				},
				.attributes = self.attributes,
				.current_color = self.current_color
			};
        }

        pub fn set_state(self: *Self, new_state: Self.State) void {
        	self.pos = new_state.pos;
        	self.attributes = new_state.attributes;
        	self.current_color = new_state.current_color;
        }

        /// get writer
        pub fn writer(self: *Self) Writer {
        	return Self.Writer{.context = self};
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

pub var tty_array: [10]Tty = [1]Tty{Tty{}} ** 10;

pub var current_tty: u8 = 0;