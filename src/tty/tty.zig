const ft = @import("../ft/ft.zig");
const vt100 = @import("vt100.zig").vt100;
const termios = @import("termios.zig");
const cc_t = termios.cc_t;
const keyboard = @import("keyboard.zig");
const ports = @import("../io/ports.zig");

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

pub const BLANK_CHAR = ' ' | (@as(u16, @intCast(@intFromEnum(Color.white))) << 8);

const MAX_INPUT : usize = 4096; // must be a power of 2

/// screen width
pub const width = 80;
/// screen height
pub const height = 25;

/// address of the mmio vga buffer
var mmio_buffer: [*]u16 = @ptrFromInt(0xB8000);

/// wether or not the cursor is on the screen.
/// initialized to false because we need to change its size on boot
var cursor_enabled: bool = false;

/// TtyN is a generic struct that represent a vt100-like terminal, it can be written and can
/// be shown on the screen with the view function, TtyN include a scrollable
/// history and various functions to control the view displacement.
/// The template parameter to TtyN is the size of the (statically allocated) history
pub fn TtyN(comptime history_size: u32) type {
	if (history_size < height)
		@compileError("TtyN: history_size must be greater than the terminal height");
	if (@popCount(MAX_INPUT) != 1)
		@compileError("MAX_INPUT must be a power of 2");
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

		/// buffer for input
        input_buffer: [MAX_INPUT]u8 = undefined,

		/// point to the end of the input area
        read_head: input_buffer_pos_t = 0,

		/// point to the beginning of the unread part of the buffer
        read_tail: input_buffer_pos_t = 0,

		/// In canonical mode, point to the beginning of the active line
        current_line_begin: input_buffer_pos_t = 0,

		/// point to the end of the processed area
        current_line_end: input_buffer_pos_t = 0,

		/// point to the first unprocessed byte in the input buffer
        unprocessed_begin: input_buffer_pos_t = 0,

		/// current termios configuration
        config: termios.termios = .{},

		const input_buffer_pos_t = ft.meta.Int(.unsigned, ft.math.log2(MAX_INPUT)); // todo

        /// Writer object type
        pub const Writer = ft.io.Writer(*Self, Self.WriteError, Self.write);
        /// Reader object type
        pub const Reader = ft.io.Reader(*Self, Self.ReadError, Self.read);

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
                self.history_buffer[line][i] = BLANK_CHAR;
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
                	var pos_to_headline : u32 = 0;
                	if (self.pos.line <= self.head_line) {
                		pos_to_headline = self.head_line - self.pos.line;
                	} else {
                		pos_to_headline = history_size + (self.pos.line -  self.head_line);
                	}
					self.pos.line += @as(u32, @intCast(actual_line_offset));
					self.pos.line %= history_size;
					if (actual_line_offset > pos_to_headline)
					{
						for (0..(@as(u32, @intCast(actual_line_offset)) -| pos_to_headline)) |_|
						{
							self.head_line += 1;
							self.head_line %= history_size;
							self.clear_line(self.head_line);
						}
					}
                }
            }
        }

		/// send keyboard input to the terminal
        pub fn input(self: *Self, s: [] const u8) void {
        	for (s) |c| self.input_char(c);
        	self.local_processing();
        }

		/// send one char as input to the terminal
        fn input_char(self: *Self, c: u8) void {
			if (self.input_processing(c)) |p| if (self.read_head +% 1 != self.read_tail) {
				self.input_buffer[self.read_head] = p;
				self.read_head +%= 1;
			};
        }

		/// perform input processing as defined by POSIX and according to the current termios configuration
        fn input_processing(self: *Self, c: u8) ?u8 {
        	return if (self.config.c_iflag.IGNCR and c == '\r') null
        	else if (self.config.c_iflag.ICRNL and c == '\r') '\n'
        	else if (self.config.c_iflag.INLCR and c == '\n') '\r'
        	else c;
        }

		/// return true if te char c is an end of line in the current termios configuration
        fn is_end_of_line(self: *Self, c: u8) bool {
        	return c == '\n' or c == self.config.c_cc[@intFromEnum(termios.cc_index.VEOL)] or c == self.config.c_cc[@intFromEnum(termios.cc_index.VEOF)];
        }

		/// perform local processing as defined by POSIX and according to the current termios configuration
        fn local_processing(self: *Self) void {
	        if (self.config.c_lflag.ICANON) {
	        	while (self.unprocessed_begin != self.read_head)
	        	{
	        		const c : u8 = self.input_buffer[self.unprocessed_begin];
					self.unprocessed_begin +%= 1;

	        		if (self.is_end_of_line(c)) {
	        			if (c != self.config.c_cc[@intFromEnum(termios.cc_index.VEOF)]) {
							self.putchar(c);
	        			}
						self.input_buffer[self.current_line_end] = c;
						self.current_line_end +%= 1;
	        			self.current_line_begin = self.current_line_end;
	        		} else if (c == self.config.c_cc[@intFromEnum(termios.cc_index.VERASE)]) {
	        			if (self.current_line_end != self.current_line_begin)
						{
							if (self.config.c_lflag.ECHO and self.config.c_lflag.ECHOE) {
								_ = self.write("\x08 \x08") catch {};
							}
							self.current_line_end -%= 1;
						}
	        		} else if (c == self.config.c_cc[@intFromEnum(termios.cc_index.VKILL)]) {
	        			while (self.current_line_end != self.current_line_begin)
						{
							if (self.config.c_lflag.ECHO and self.config.c_lflag.ECHOE) {
								_ = self.write("\x08 \x08") catch {};
							}
							self.current_line_end -%= 1;
						}
						// todo ECHOK
	        		} else {
						self.input_buffer[self.current_line_end] = c;
						self.current_line_end +%= 1;
						if (self.config.c_lflag.ECHO or (c == '\n' and self.config.c_lflag.ECHONL))
						{
							if (self.config.c_lflag.ECHOCTL and c & 0b11100000 == 0) {
								self.putchar('^');
								self.putchar(c | 0b01000000);
							} else {
								self.putchar(c);
							}
						}
	        		}
	        	}
	        	self.read_head = self.current_line_end;
	        	self.unprocessed_begin = self.current_line_end;
	        } else {
	        	while (self.current_line_end != self.read_head)
	        	{
					if (self.config.c_lflag.ECHO or (self.input_buffer[self.current_line_end] == '\n' and self.config.c_lflag.ECHONL))
						self.putchar(self.input_buffer[self.current_line_end]);
	        		self.current_line_end +%= 1;
	        	}
	        }
        }

		/// put the char c in the output buffer
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

		/// put a character to the ouput buffer with whitespace processing
        fn process_whitespaces(self: *Self, c: u8) void {
            	switch (c) {
					'\n' => {
						if (self.config.c_oflag.ONLRET)
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
						// todo?
						// self.move_cursor(height, -@as(i32, @intCast(self.pos.col)));
					},
					' '...'~', 0x80...0xfe => {
						self.put_char_to_buffer(c);
					},
					else => {}, // unknown characters are discarded
				}
        }

		/// perform output processing as defined by POSIX and according to the current termios configuration
        fn output_processing(self: *Self, c: u8) void {
        	if (self.config.c_oflag.OPOST)
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
					} else {
						var tmp: @TypeOf(self.escape_buffer) = undefined;
						@memcpy(&tmp, &self.escape_buffer);
						@memset(&self.escape_buffer, 0);
						self.write_state = .Normal;
						_ = self.write(tmp[0..]) catch {};
						self.putchar_no_flush(c);
					},
					.Normal => {
						if (self.config.c_oflag.ONLCR and c == '\n')
						{
							self.process_whitespaces('\r');
							self.process_whitespaces('\n');
						}
						else if (self.config.c_oflag.OCRNL and c == '\r')
						{
							self.process_whitespaces('\n');
						}
						else if (self.config.c_oflag.OCRNL and c == '\r' and self.pos.col == 0)
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

        /// write the character c to the terminal without flush
        fn putchar_no_flush(self: *Self, c: u8) void {
			self.output_processing(c);
        }

        /// write the character c to the terminal with flush
        pub fn putchar(self: *Self, c: u8) void {
        	self.putchar_no_flush(c);
			self.view();
        }

        /// read bytes from the terminal and store them in s, suitable for use with ft.io.Reader
        pub fn read(self: *Self, s: [] u8) Self.ReadError!usize {
        	// todo time/min
        	var count : usize = 0;
        	for (s) |*c| {
        		while  (self.read_tail == self.current_line_begin and self.read_head +% 1 != self.read_tail) {
        			keyboard.kb_read();
        		}

        		c.* = self.input_buffer[self.read_tail];
        		if (self.read_tail == self.current_line_begin)
        			self.current_line_begin +%= 1;
        		self.read_tail +%= 1;
        		count += 1;
	        	if (self.config.c_lflag.ICANON and self.is_end_of_line(c.*))
	        	{
        			if (c.* == self.config.c_cc[@intFromEnum(termios.cc_index.VEOF)])
        				count -= 1;
	        		break;
	        	}
        	}
        	return count;
        }

        /// write the string s to the buffer and return the number of bites writen, suitable for use with ft.io.Writer
        pub fn write(self: *Self, s: []const u8) Self.WriteError!usize {
            var ret: usize = 0;
            for (s) |c| {
                self.putchar_no_flush(c);
                ret += 1;
            }
			self.view();
            return ret;
        }

        /// return the current terminal state for save/restore
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

        /// set the current terminal state
        pub fn set_state(self: *Self, new_state: Self.State) void {
        	self.pos = new_state.pos;
        	self.attributes = new_state.attributes;
        	self.current_color = new_state.current_color;
        }

        /// get writer
        pub fn writer(self: *Self) Writer {
        	return Self.Writer{.context = self};
        }

        /// get reader
        pub fn reader(self: *Self) Reader {
        	return Self.Reader{.context = self};
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

		/// soft scroll in the terminal history
        pub fn scroll(self: *Self, off: i32) void {
            if (off > 0) {
                self.scroll_offset += @intCast(off);
            } else {
                self.scroll_offset -|= @intCast(-off);
            }
            if (self.scroll_offset >= history_size)
            	self.scroll_offset = history_size - 1;
            self.view();
        }


		/// enable vga cursor
		pub fn enable_cursor(_: *Self) void {
        	const cursor_start : u8 = 0;
        	const cursor_end : u8 = 15;
        	ports.outb(.vga_idx_reg, 0x0A);
        	ports.outb(.vga_io_reg, (ports.inb(.vga_io_reg) & 0xC0) | cursor_start);
        	ports.outb(.vga_idx_reg, 0x0B);
        	ports.outb(.vga_io_reg, (ports.inb(.vga_io_reg) & 0xE0) | cursor_end);
			cursor_enabled = true;
        }

		/// disable vga cursor
        pub fn disable_cursor(_: *Self) void {
			ports.outb(.vga_idx_reg, 0x0A);
			ports.outb(.vga_io_reg, 0x20);
			cursor_enabled = false;
        }

		/// print the cursor at the current position on the screen
        fn put_cursor(self: *Self) void {
        	const offset = (self.head_line + history_size - self.scroll_offset) % history_size;
        	const is_visible : bool = if (offset < height)
					self.pos.line > ((offset + history_size - height) % history_size) or self.pos.line <= offset
				else
					self.pos.line > (offset - height) and self.pos.line <= offset;
			if (is_visible)
			{
				if (!cursor_enabled)
					self.enable_cursor();

				const pos = self.get_state().pos;
				const index: u32 = pos.line * width + pos.col;
				ports.outb(.vga_idx_reg, 0x0F);
				ports.outb(.vga_io_reg, @intCast(index & 0xff));
				ports.outb(.vga_idx_reg, 0x0E);
				ports.outb(.vga_io_reg, @intCast((index >> 8) & 0xff));
			}
			else
			{
				if (cursor_enabled)
					self.disable_cursor();
			}
        }

        /// print the buffer to the vga buffer
        pub fn view(self: *Self) void {
        	if (&tty_array[current_tty] != self)
        		return;
            for (0..height) |l| {
                for (0..width) |c| {
                    const view_line = (history_size + history_size + self.head_line + 1 -| height -| self.scroll_offset) % history_size;
                    const buffer_line = (view_line + l) % history_size;
                    mmio_buffer[l * width + c] = if (((buffer_line < self.head_line or (buffer_line == self.head_line))) or (self.head_line < view_line and buffer_line >= view_line))
                        switch (self.history_buffer[buffer_line][c]) {
							0 => BLANK_CHAR,
							else => |char| char
                        }
                    else
						BLANK_CHAR;
                }
            }
			self.put_cursor();
        }
    };
}

/// Tty is a specialisation of TtyN with an history size of 1000
pub const Tty = TtyN(1000);

/// maximum tty index for tty_array
pub const max_tty = 9;

///	array of all the available ttys
pub var tty_array: [max_tty + 1]Tty = [1]Tty{Tty{}} ** 10;

/// index of the active tty
pub var current_tty: u8 = 0;

pub fn get_tty() *Tty {
	return &tty_array[current_tty];
}

/// set the current tty
pub fn set_tty(n: u8) !void {
	if (n > max_tty)
		return error.InvalidTty;
	current_tty = n;
	tty_array[current_tty].view();
}

/// return the reader object of the current tty
pub inline fn get_reader() Tty.Reader {
	return tty_array[current_tty].reader();
}

/// return the writer object of the current tty
pub inline fn get_writer() Tty.Writer {
	return tty_array[current_tty].writer();
}

/// print a formatted string to the current terminal
pub inline fn printk(comptime fmt: []const u8, args: anytype) void {
	get_writer().print(fmt, args) catch {};
}