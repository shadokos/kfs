const tty = @import("tty/tty.zig");
const utils = @import("shell/utils.zig");

const logo =
"    +   .                                   \n" ++
"    :  :                                    \n" ++
"     . ;                                    \n" ++
" -..   +$                                   \n" ++
"    `+_ .$                                  \n" ++
"      _ +;$;  $$+                           \n" ++
"   +`    +$$$$$$$$$$$$x.                    \n" ++
" x`         X$$$$$$$$$$$$x                  \n" ++
";          $$$+$$$$$$$$$$$$.                \n" ++
":         +$$$+;$$$$$$$$$$$$$$$$x.          \n" ++
"        .o;-----.$$$$$$$$$$$$$$$$$$x.       \n" ++
"       $$ $$;-'`   ;X$$$$$$$$$$$$$$$$$+     \n" ++
"      $$ $X $$$$$;;$x $$.$   :$$$$$$$$$$    \n" ++
"      . $$ $$  $ $ .$  $        $$$$$$$$$   \n" ++
"     .  : $$  $; $  $ $           $$;$$$$x  \n" ++
"      ..  :   $x $  $$ $x          .  $$$$  \n" ++
"        : :    + +   $$  X            .$$$+ \n" ++
"               .  ;    x              $$$$  \n" ++
"                   ;                .$$$$X  \n" ++
"       $&&&  &&&  &&&&&&  ;&&&&;   $$$$$$.  \n" ++
"       .&&x &&.   x&&:   &&&     :$$$$$$$   \n" ++
"       .&&x&&     x&&&&  x&&&&$  $$$$$$     \n" ++
"       .&&x&&&    x&&:      &&&&;           \n" ++
"       .&&x &&&   x&&:   x   .&&;           \n" ++
"       $&&&  &&&; &&&&   ;&&&&&             \n";




const letter_o =
"\x20\xb3\xb3\xb3\x20\n" ++
"\xb3\x20\x20\x20\xb3\n" ++
"\xb3\x20\x20\x20\xb3\n" ++
"\xb3\x20\x20\x20\xb3\n" ++
"\x20\xb3\xb3\xb3\x20\n";

const letter_h =
"\xb3\x20\x20\x20\xb3\n" ++
"\xb3\x20\x20\x20\xb3\n" ++
"\xb3\xb3\xb3\xb3\xb3\n" ++
"\xb3\x20\x20\x20\xb3\n" ++
"\xb3\x20\x20\x20\xb3\n";

const letter_n =
"\xb3\x20\x20\x20\xb3\n" ++
"\xb3\xb3\x20\x20\xb3\n" ++
"\xb3\x20\xb3\x20\xb3\n" ++
"\xb3\x20\x20\xb3\xb3\n" ++
"\xb3\x20\x20\x20\xb3\n";

const letter_exclamation =
"\x20\x20\xb3\x20\x20\n" ++
"\x20\x20\xb3\x20\x20\n" ++
"\x20\x20\xb3\x20\x20\n" ++
"\x20\x20\x20\x20\x20\n" ++
"\x20\x20\xb3\x20\x20\n";

pub fn print_ascii_art(
	image: []const u8,
	coord: struct {x: u16, y: u16},
	colors: struct {bg: []const u8, fg: []const u8}
) void {
	var _coord = coord;
	tty.printk("\x1b[2m\x1b[37m{s}{s}", .{colors.bg, colors.fg});
	for (image) |c| switch (c) {
		' ' => _coord.x += 1,
		'\n' => {
			_coord.x = coord.x;
			_coord.y += 1;
		},
		else => {
			tty.printk(
				"\x1b[{d};{d}H{s}",
				.{_coord.y, _coord.x, [1]u8{c}},
			);
			_coord.x += 1;
		},
	};
}

pub fn screen_of_death(comptime format: []const u8, args: anytype) void {
	const dim	   = "\x1b[2m";
	const bg_red   = "\x1b[41m";
	const bg_black = "\x1b[0m";
	const fg_white = "\x1b[37m";
	const fg_black = "\x1b[30m" ++ dim;

	tty.printk(bg_red ++ "{s}", .{(" " ** (tty.width*tty.height))});
	tty.get_tty().scroll(1);
	print_ascii_art(logo, .{.x = 37, .y = 0}, .{.bg = bg_red, .fg = fg_white});
	print_ascii_art(letter_o, .{.x = 3, .y = 2}, .{.bg = bg_black, .fg = fg_black});
	print_ascii_art(letter_h, .{.x = 10, .y = 2}, .{.bg = bg_black, .fg = fg_black});
	print_ascii_art(letter_n, .{.x = 21, .y = 2}, .{.bg = bg_black, .fg = fg_black});
	print_ascii_art(letter_o, .{.x = 28, .y = 2}, .{.bg = bg_black, .fg = fg_black});
	print_ascii_art(letter_exclamation, .{.x = 33, .y = 2}, .{.bg = bg_black, .fg = fg_black});
	tty.printk("\x1b[9;3H" ++ fg_black ++ bg_red ++ "{s}", .{
		"######## KERNEL PANIC! #########"
	});
	tty.printk("\x1b[11;3H" ++ utils.reset ++ fg_white ++ bg_red, .{});
	tty.printk(format, args);
}