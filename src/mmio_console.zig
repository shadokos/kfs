const ft = @import("ft/ft.zig");
const Writer = @import("std").io.Writer;
const fmt = @import("std").fmt;

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

const Attribute = enum {
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
const width = 80;
/// screen height
const height = 25;

/// ft.Writer implementation for BufferN
fn BufferWriter(comptime history_size: u32) type { return Writer(*BufferN(history_size), BufferN(history_size).write_error, BufferN(history_size).write); }

/// address of the mmio vga buffer
var mmio_buffer: [*]u16 = @ptrFromInt(0xB8000);

/// BufferN is a generic struct that represent a vt100-like terminal, it can be written and can
/// be shown on the screen with the view function, BufferN include a scrollable
/// history and various functions to control the view displacement.
/// The template parameter to BufferN is the size of the (statically allocated) history
pub fn BufferN(comptime history_size: u32) type {
    return struct {
        /// history buffer
        history_buffer: [history_size][width]u16 = undefined,

        /// current color
        current_color: u16 = 0,

        /// attributes
        attributes: u32 = 0,

        /// current position in the history buffer
        pos: struct { line: u32, col: u32 } = .{ .line = 0, .col = 0 },

		/// the lower line writen
        head_line: u32 = 0,

        /// current offset for view (0 mean bottom)
        scroll_offset: u32 = 0,

        /// writer for the buffer
        writer: BufferWriter(history_size) = undefined,

		/// true if were currently parsing a term cap code
        escape_mode: bool = false,

		/// buffer for escape sequences
        escape_buffer: [10:0]u8 = [_:0]u8{0} ** 10,

        pub const write_error = error{};

        const Self = @This();

        /// clear line line in the history buffer
        fn clear_line(self: *Self, line: u32) void {
            for (0..width) |i|
                self.history_buffer[line][i] = ' ';
        }

		/// move the curser of line_offset vertically and col_offset horizontally
        fn move_cursor(self: *BufferN(history_size), line_offset: i32, col_offset: i32) void {

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

		/// handle move escape codes
        fn handle_move(self: *BufferN(history_size)) void {
            const len = ft.mem.indexOfSentinel(u8, 0, &self.escape_buffer);
            var n: i32 = ft.fmt.parseInt(i32, self.escape_buffer[1 .. len - 1], 10) catch 0;
            switch (self.escape_buffer[len - 1]) {
                'A' => {self.move_cursor(-n, 0);},
                'B' => {self.move_cursor(n, 0);},
                'C' => {self.move_cursor(0, -n);},
                'D' => {self.move_cursor(0, n);},
                else => {},
            }
        }

		/// handle set attributes escape codes
        fn handle_set_attribute(self: *BufferN(history_size)) void {
            const len = ft.mem.indexOfSentinel(u8, 0, &self.escape_buffer);
            var n: u32 = ft.fmt.parseInt(u32, self.escape_buffer[1 .. len - 1], 10) catch 0;
        	switch (n) {
        		@intFromEnum(Attribute.reset) => {self.attributes = 0;},
        		@intFromEnum(Attribute.bold)...@intFromEnum(Attribute.hidden) => {self.attributes |= @as(u16, 1) << @intCast(n);},
        		30...37 => {self.set_font_color(
        			switch (n) {
        				30 => Color.black,
        				31 => Color.red,
        				32 => Color.green,
        				33 => Color.brown,
        				34 => Color.blue,
        				35 => Color.magenta,
        				36 => Color.cyan,
        				37 => Color.white,
        				else => Color.white
        			}
        		); },
        		40...47 => {self.set_background_color(
					switch (n) {
						40 => Color.black,
						41 => Color.red,
						42 => Color.green,
						43 => Color.brown,
						44 => Color.blue,
						45 => Color.magenta,
						46 => Color.cyan,
						47 => Color.white,
						else => Color.black
					}
				); },
        		else => {}
        	}
        }

		/// handle set scroll escape codes
        fn handle_scroll(self: *BufferN(history_size)) void {
        	switch (self.escape_buffer[1])
        	{
        		'D' => {self.scroll(1);},
        		'M' => {self.scroll(-1);},
        		else => {}
        	}
        }

		/// handle set clear line escape codes
        fn handle_clearline(self: *BufferN(history_size)) void {
            const len = ft.mem.indexOfSentinel(u8, 0, &self.escape_buffer);
            var n: i32 = ft.fmt.parseInt(i32, self.escape_buffer[2 .. len - 1], 10) catch 0;
        	switch (n)
        	{
        		0 => {
					for (0..self.pos.col + 1) |i| {
						self.history_buffer[self.pos.line][i] = ' ';
					}
        		},
        		1 => {
					for (self.pos.col..width) |i| {
						self.history_buffer[self.pos.line][i] = ' ';
					}
        		},
        		2 => {self.clear_line(self.pos.line);},
        		else => {}
        	}
        }

		/// handle set clear screen escape codes
        fn handle_clearscreen(self: *BufferN(history_size)) void {
            const len = ft.mem.indexOfSentinel(u8, 0, &self.escape_buffer);
            var n: i32 = ft.fmt.parseInt(i32, self.escape_buffer[2 .. len - 1], 10) catch 0;
            const screen_bottom = (self.head_line + history_size - self.scroll_offset) % history_size;
            var screen_top = (screen_bottom + history_size - height + 1) % history_size;

        	switch (n)
        	{
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
        		else => {}
        	}
        }

		/// handle set goto escape codes
        fn handle_goto(self: *BufferN(history_size)) void {
            const semicolon_pos = ft.mem.indexOfScalarPos(u8, &self.escape_buffer, 2, ';') orelse 0;
            var v: u32 = 0;
            var h: u32 = 0;
            if (semicolon_pos != 0)
            {
				const len = ft.mem.indexOfSentinel(u8, 0, &self.escape_buffer);
				v = ft.fmt.parseInt(u32, self.escape_buffer[2 .. semicolon_pos], 10) catch 0;
				h = ft.fmt.parseInt(u32, self.escape_buffer[semicolon_pos + 1 .. len - 1], 10) catch 0;
            }
            self.escape_mode = false;
            var off_v : i32 = -@as(i32, @intCast(self.pos.line)) + @rem(@as(i32,@intCast(self.head_line)) -| @as(i32,@intCast(self.scroll_offset)) -| @as(i32,@intCast(height - 1)) + @as(i32,@intCast(v)), history_size);
            var off_h : i32 = -@as(i32, @intCast(self.pos.col)) + @as(i32, @intCast(h));
            self.move_cursor(off_v, off_h);
        }

        fn handle_nothing(_: *BufferN(history_size)) void {}

		/// compare the escape buffer with an escape code description (^ match any natural number)
        fn compare_prefix(prefix: [:0]const u8, buffer: [:0]const u8) bool {
            var i: u32 = 0;
            var j: u32 = 0;

            while (prefix[i] != 0 and buffer[j] != 0) {
                if (prefix[i] == '^') {
                	if (!ft.ascii.isDigit(buffer[j]))
                		return false;
                    while (buffer[j] != 0 and ft.ascii.isDigit(buffer[j])) {
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

		/// check if the escape buffer contains a full escape code and execute it
		/// see https://espterm.github.io/docs/VT100%20escape%20codes.html
        fn handle_escape(self: *BufferN(history_size)) void {
            const map = [_]struct { prefix: [:0]const u8, f: *const fn (*BufferN(history_size)) void } {
					.{ .prefix = "^[[20h", .f = &handle_nothing }, // new line mode
					.{ .prefix = "^[[?^h", .f = &handle_nothing }, // terminal config
					.{ .prefix = "^[[20l", .f = &handle_nothing }, // line feed mode
					.{ .prefix = "^[[?^l", .f = &handle_nothing }, // terminal config
					.{ .prefix = "^[=", .f = &handle_nothing }, // alternate keypad mode
					.{ .prefix = "^[>", .f = &handle_nothing }, // numeric keypad mode
					.{ .prefix = "[(A", .f = &handle_nothing }, // special chars
					.{ .prefix = "[)A", .f = &handle_nothing }, // special chars
					.{ .prefix = "[(B", .f = &handle_nothing }, // special chars
					.{ .prefix = "[)B", .f = &handle_nothing }, // special chars
					.{ .prefix = "[(^", .f = &handle_nothing }, // special chars
					.{ .prefix = "[)^", .f = &handle_nothing }, // special chars
					.{ .prefix = "[N", .f = &handle_nothing }, // single shift 2
					.{ .prefix = "[D", .f = &handle_nothing }, // single shift 3
					.{ .prefix = "[m", .f = &handle_set_attribute },
					.{ .prefix = "[^m", .f = &handle_set_attribute },
					.{ .prefix = "[[^;^r", .f = &handle_nothing }, // Set top and bottom line#s of a window
					.{ .prefix = "[^A", .f = &handle_move },
					.{ .prefix = "[^B", .f = &handle_move },
					.{ .prefix = "[^C", .f = &handle_move },
					.{ .prefix = "[^D", .f = &handle_move },
					.{ .prefix = "[[H", .f = &handle_goto },
					.{ .prefix = "[[;H", .f = &handle_goto },
					.{ .prefix = "[[^;^H", .f = &handle_goto },
					.{ .prefix = "[[f", .f = &handle_goto },
					.{ .prefix = "[[;f", .f = &handle_goto },
					.{ .prefix = "[[^;^f", .f = &handle_goto },
					.{ .prefix = "[D", .f = &handle_scroll },
					.{ .prefix = "[M", .f = &handle_scroll },
					.{ .prefix = "[E", .f = &handle_nothing }, // move to next line
					// .{ .prefix = "[7", .f = &handle_nothing }, // save cursor pos and attributes
					// .{ .prefix = "[8", .f = &handle_nothing }, // restore cursor pos and attributes
					.{ .prefix = "[H", .f = &handle_nothing }, // set tab at current column
					.{ .prefix = "[g", .f = &handle_nothing }, // Clear a tab at the current column
					.{ .prefix = "[0g", .f = &handle_nothing }, // Clear a tab at the current column
					.{ .prefix = "[3g", .f = &handle_nothing }, // Clear all tabs
					.{ .prefix = "[#3", .f = &handle_nothing }, // Double-height letters, top half
					.{ .prefix = "[#4", .f = &handle_nothing }, // Double-height letters, bottom half
					.{ .prefix = "[#5", .f = &handle_nothing }, // Single width, single height letters
					.{ .prefix = "[#6", .f = &handle_nothing }, // Double width, single height letters
					.{ .prefix = "[[K", .f = &handle_clearline },
					.{ .prefix = "[[^K", .f = &handle_clearline },
					.{ .prefix = "[[J", .f = &handle_clearscreen },
					.{ .prefix = "[[^J", .f = &handle_clearscreen },
					.{ .prefix = "[5n", .f = &handle_nothing }, // Device status report
					.{ .prefix = "[6n", .f = &handle_nothing }, // get cursor pos
					.{ .prefix = "[[c", .f = &handle_nothing }, // identify terminal type
					.{ .prefix = "[[0c", .f = &handle_nothing }, // identify terminal type
					.{ .prefix = "[c", .f = &handle_nothing }, // Reset terminal to initial state
					.{ .prefix = "[#8", .f = &handle_nothing }, // vt100
					.{ .prefix = "[[2;1y", .f = &handle_nothing }, // vt100
					.{ .prefix = "[[2;2y", .f = &handle_nothing }, // vt100
					.{ .prefix = "[[2;9y", .f = &handle_nothing }, // vt100
					.{ .prefix = "[[2;10y", .f = &handle_nothing }, // vt100
					.{ .prefix = "[[0q", .f = &handle_nothing }, // vt100
					.{ .prefix = "[[1q", .f = &handle_nothing }, // vt100
					.{ .prefix = "[[2q", .f = &handle_nothing }, // vt100
					.{ .prefix = "[[3q", .f = &handle_nothing }, // vt100
					.{ .prefix = "[[4q", .f = &handle_nothing }, // vt100
            	};
            for (map) |e| {
                if (compare_prefix(e.prefix, &self.escape_buffer)) {
                    self.escape_mode = false;
                    e.f(self);
                    @memset(&self.escape_buffer, 0);
                    return;
                }
            }
        }

        /// write the character c in the buffer
        pub fn putchar(self: *Self, c: u8) void {
            if (self.escape_mode) {
            	if (ft.mem.len(@as([*:0]u8, &self.escape_buffer)) < self.escape_buffer.len - 1)
                {
                	self.escape_buffer[ft.mem.len(@as([*:0]u8, &self.escape_buffer))] = c;
					self.handle_escape();
					return;
                }
                else
                {
                	self.escape_mode = false;
                	return;
                }
            }
            switch (c) {
                0x1b => {
                    self.escape_mode = true;
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
                else => {},
            }
            if (self.pos.col >= width) {
                self.pos.line += 1;
                self.pos.col = 0;
            }
            if (self.pos.line >= history_size)
                self.pos.line = 0;
        }

        /// write the string s to the buffer and return the number of bites writen, suitable for use with ft.io.Writer
        pub fn write(self: *Self, s: []const u8) BufferN(history_size).write_error!usize {
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
            self.writer = BufferWriter(history_size){ .context = self };
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

/// Buffer is a specialisation of BufferN with an history size of 1000
pub const Buffer = BufferN(1000);
