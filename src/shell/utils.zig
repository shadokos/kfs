const tty = @import("../tty/tty.zig");

pub const inverse = "\x1b[7m";
pub const red = "\x1b[31m";
pub const green = "\x1b[32m";
pub const yellow = "\x1b[33m";
pub const blue = "\x1b[34m";
pub const magenta = "\x1b[35m";
pub const cyan = "\x1b[36m";
pub const white = "\x1b[37m";
pub const bg_red = "\x1b[41m";
pub const bg_green = "\x1b[42m";
pub const bg_yellow = "\x1b[43m";
pub const bg_blue = "\x1b[44m";
pub const bg_magenta = "\x1b[45m";
pub const bg_cyan = "\x1b[46m";
pub const bg_white = "\x1b[47m";
pub const reset = "\x1b[0m";

const prompt: *const [2:0]u8 = "$>";

pub fn ensure_newline() void {
	tty.printk("{s}\x1b[{d}C\r", .{
		inverse ++ "%" ++ reset, // No newline char: '%' character in reverse
		tty.width - 2, // Move cursor to the end of the line or on the next line if the line is not empty
	});
}

pub fn print_error(msg: []const u8) void {
	ensure_newline();
	tty.printk(red ++ "Error:" ++ reset ++ " {s}\n", .{msg});
}

pub fn print_prompt(status_code: usize) void {
	ensure_newline();
	tty.printk("{s}{s}" ++ reset ++ " ", .{ // print the prompt:
		if (status_code != 0) red else cyan, // prompt collor depending on the last command status
		prompt, // prompt
	});
}