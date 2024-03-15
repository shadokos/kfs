const ft = @import("../ft/ft.zig");
const tty = @import("tty.zig");

pub fn vt100(comptime history_size: u32) type {
    return struct {
        /// handle move escape codes
        fn handle_move(terminal: *tty.TtyN(history_size), buffer: [:0]const u8) void {
            const len = ft.mem.indexOfSentinel(u8, 0, buffer);
            var n: i32 = ft.fmt.parseInt(i32, buffer[1 .. len - 1], 10) catch 1;
            switch (buffer[len - 1]) {
                'A' => {
                    terminal.move_cursor(-n, 0);
                },
                'B' => {
                    terminal.move_cursor(n, 0);
                },
                'C' => {
                    terminal.move_cursor(0, n);
                },
                'D' => {
                    terminal.move_cursor(0, -n);
                },
                else => {},
            }
        }

        /// handle set attributes escape codes
        fn handle_set_attribute(terminal: *tty.TtyN(history_size), buffer: [:0]const u8) void {
            const len = ft.mem.indexOfSentinel(u8, 0, buffer);
            var n: u32 = ft.fmt.parseInt(u32, buffer[1 .. len - 1], 10) catch 0;
            switch (n) {
                @intFromEnum(tty.Attribute.reset) => {
                    terminal.attributes = 0;
                    terminal.reset_color();
                },
                @intFromEnum(tty.Attribute.bold)...@intFromEnum(tty.Attribute.hidden) => {
                    terminal.attributes |= @as(u16, 1) << @intCast(n);
                },
                30...37 => {
                    terminal.set_font_color(switch (n) {
                        30 => tty.Color.black,
                        31 => tty.Color.red,
                        32 => tty.Color.green,
                        33 => tty.Color.brown,
                        34 => tty.Color.blue,
                        35 => tty.Color.magenta,
                        36 => tty.Color.cyan,
                        37 => tty.Color.light_grey,
                        else => tty.Color.light_grey,
                    });
                },
                40...47 => {
                    terminal.set_background_color(switch (n) {
                        40 => tty.Color.black,
                        41 => tty.Color.red,
                        42 => tty.Color.green,
                        43 => tty.Color.brown,
                        44 => tty.Color.blue,
                        45 => tty.Color.magenta,
                        46 => tty.Color.cyan,
                        47 => tty.Color.light_grey,
                        else => tty.Color.black,
                    });
                },
                else => {},
            }
        }

        /// handle save and restore
        fn handle_save(terminal: *tty.TtyN(history_size), buffer: [:0]const u8) void {
            const saved_state = struct {
                var value: ?tty.TtyN(history_size).State = null;
            };
            switch (buffer[0]) {
                '7' => saved_state.value = terminal.get_state(),
                '8' => if (saved_state.value) |value| terminal.set_state(value),
                else => unreachable,
            }
        }

        /// handle set clear line escape codes
        fn handle_clearline(terminal: *tty.TtyN(history_size), buffer: [:0]const u8) void {
            const len = ft.mem.indexOfSentinel(u8, 0, buffer);
            var n: i32 = ft.fmt.parseInt(i32, buffer[1 .. len - 1], 10) catch 0;
            switch (n) {
                0 => {
                    for (terminal.pos.col..tty.width) |i| {
                        terminal.history_buffer[terminal.pos.line][i] = tty.BLANK_CHAR;
                    }
                },
                1 => {
                    for (0..terminal.pos.col + 1) |i| {
                        terminal.history_buffer[terminal.pos.line][i] = tty.BLANK_CHAR;
                    }
                },
                2 => {
                    terminal.clear_line(terminal.pos.line);
                },
                else => {},
            }
        }

        /// handle set clear screen escape codes
        fn handle_clearscreen(terminal: *tty.TtyN(history_size), buffer: [:0]const u8) void {
            const len = ft.mem.indexOfSentinel(u8, 0, buffer);
            var n: i32 = ft.fmt.parseInt(i32, buffer[1 .. len - 1], 10) catch 0;
            const screen_bottom = (terminal.head_line + history_size - terminal.scroll_offset) % history_size;
            var screen_top = (screen_bottom + history_size - tty.height + 1) % history_size;

            switch (n) {
                0 => {
                    screen_top = terminal.pos.line;
                    while (screen_top != screen_bottom) {
                        terminal.clear_line(screen_top);
                        screen_top += 1;
                        screen_top %= history_size;
                    }
                    terminal.clear_line(screen_top);
                },
                1 => {
                    while (screen_top != terminal.pos.line) {
                        terminal.clear_line(screen_top);
                        screen_top += 1;
                        screen_top %= history_size;
                    }
                    terminal.clear_line(screen_top);
                },
                2 => {
                    while (screen_top != screen_bottom) {
                        terminal.clear_line(screen_top);
                        screen_top += 1;
                        screen_top %= history_size;
                    }
                    terminal.clear_line(screen_top);
                },
                else => {},
            }
        }

        /// handle set goto escape codes
        fn handle_goto(terminal: *tty.TtyN(history_size), buffer: [:0]const u8) void {
            const semicolon_pos = ft.mem.indexOfScalarPos(u8, buffer, 1, ';') orelse 0;
            var v: u32 = 0;
            var h: u32 = 0;
            if (semicolon_pos != 0) {
                const len = ft.mem.indexOfSentinel(u8, 0, buffer);
                v = ft.fmt.parseInt(u32, buffer[1..semicolon_pos], 10) catch 0;
                h = ft.fmt.parseInt(u32, buffer[semicolon_pos + 1 .. len - 1], 10) catch 0;
            }
            var off_v: i32 = -@as(i32, @intCast(terminal.pos.line)) +
                @mod(@as(i32, @intCast(terminal.head_line)) -
                @as(i32, @intCast(terminal.scroll_offset)) -
                @as(i32, @intCast(tty.height - 1)) +
                @as(i32, @intCast(v)), history_size);
            var off_h: i32 = -@as(i32, @intCast(terminal.pos.col)) + @as(i32, @intCast(h));
            terminal.move_cursor(off_v, off_h);
        }

        fn handle_get_pos(terminal: *tty.TtyN(history_size), _: [:0]const u8) void {
            var buffer: [100]u8 = [1]u8{0} ** 100;
            var slice = ft.fmt.bufPrint(&buffer, "\x1b{d};{d}R", .{
                terminal.get_state().pos.line,
                terminal.get_state().pos.col,
            }) catch return;

            terminal.input(slice);
        }

        fn handle_nothing(_: *tty.TtyN(history_size), _: [:0]const u8) void {}

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
        pub fn handle_escape(terminal: *tty.TtyN(history_size), buffer: [:0]const u8) error{InvalidEscape}!bool {
            const map = [_]struct {
                prefix: [:0]const u8,
                f: *const fn (*tty.TtyN(history_size), buffer: [:0]const u8) void,
            }{
                .{ .prefix = "[20h", .f = &handle_nothing }, // new line mode
                .{ .prefix = "[?^h", .f = &handle_nothing }, // terminal config
                .{ .prefix = "[20l", .f = &handle_nothing }, // line feed mode
                .{ .prefix = "[?^l", .f = &handle_nothing }, // terminal config
                .{ .prefix = "=", .f = &handle_nothing }, // alternate keypad mode
                .{ .prefix = ">", .f = &handle_nothing }, // numeric keypad mode
                .{ .prefix = "(A", .f = &handle_nothing }, // special chars
                .{ .prefix = ")A", .f = &handle_nothing }, // special chars
                .{ .prefix = "(B", .f = &handle_nothing }, // special chars
                .{ .prefix = ")B", .f = &handle_nothing }, // special chars
                .{ .prefix = "(^", .f = &handle_nothing }, // special chars
                .{ .prefix = ")^", .f = &handle_nothing }, // special chars
                .{ .prefix = "N", .f = &handle_nothing }, // single shift 2
                .{ .prefix = "O", .f = &handle_nothing }, // single shift 3
                .{ .prefix = "[m", .f = &handle_set_attribute },
                .{ .prefix = "[^m", .f = &handle_set_attribute },
                .{ .prefix = "[^;^r", .f = &handle_nothing }, // Set top and bottom line#s of a window
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
                .{ .prefix = "E", .f = &handle_nothing }, // move to next line
                .{ .prefix = "7", .f = &handle_save }, // save cursor pos and attributes
                .{ .prefix = "8", .f = &handle_save }, // restore cursor pos and attributes
                .{ .prefix = "H", .f = &handle_nothing }, // set tab at current column
                .{ .prefix = "[g", .f = &handle_nothing }, // Clear a tab at the current column
                .{ .prefix = "[0g", .f = &handle_nothing }, // Clear a tab at the current column
                .{ .prefix = "[3g", .f = &handle_nothing }, // Clear all tabs
                .{ .prefix = "#3", .f = &handle_nothing }, // Double-height letters, top half
                .{ .prefix = "#4", .f = &handle_nothing }, // Double-height letters, bottom half
                .{ .prefix = "#5", .f = &handle_nothing }, // Single width, single tty.height letters
                .{ .prefix = "#6", .f = &handle_nothing }, // Double width, single tty.height letters
                .{ .prefix = "[K", .f = &handle_clearline },
                .{ .prefix = "[^K", .f = &handle_clearline },
                .{ .prefix = "[J", .f = &handle_clearscreen },
                .{ .prefix = "[^J", .f = &handle_clearscreen },
                .{ .prefix = "5n", .f = &handle_nothing }, // Device status report todo
                .{ .prefix = "0n", .f = &handle_nothing }, // Device status report response KO
                .{ .prefix = "3n", .f = &handle_nothing }, // Device status report response OK
                .{ .prefix = "6n", .f = &handle_get_pos }, // get cursor pos
                .{ .prefix = "^;^R", .f = &handle_nothing }, // get cursor pos response
                .{ .prefix = "[c", .f = &handle_nothing }, // identify terminal type todo
                .{ .prefix = "[0c", .f = &handle_nothing }, // identify terminal type
                .{ .prefix = "?1;^c", .f = &handle_nothing }, // identify terminal type response
                .{ .prefix = "c", .f = &handle_nothing }, // Reset terminal to initial state
                .{ .prefix = "#8", .f = &handle_nothing }, // vt100
                .{ .prefix = "[2;1y", .f = &handle_nothing }, // vt100
                .{ .prefix = "[2;2y", .f = &handle_nothing }, // vt100
                .{ .prefix = "[2;9y", .f = &handle_nothing }, // vt100
                .{ .prefix = "[2;10y", .f = &handle_nothing }, // vt100
                .{ .prefix = "[0q", .f = &handle_nothing }, // vt100
                .{ .prefix = "[1q", .f = &handle_nothing }, // vt100
                .{ .prefix = "[2q", .f = &handle_nothing }, // vt100
                .{ .prefix = "[3q", .f = &handle_nothing }, // vt100
                .{ .prefix = "[4q", .f = &handle_nothing }, // vt100
            };
            for (map) |e| {
                if (compare_prefix(e.prefix, buffer)) {
                    e.f(terminal, buffer);
                    return true;
                }
            }
            return false;
        }
    };
}
