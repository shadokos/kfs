const ft = @import("ft.zig");

pub const whitespace = [_]u8{ ' ', '\t', '\n', '\r', 11, 12 };

pub fn isDigit(c: u8) bool {
	return c >= '0' and c <= '9';
}

pub fn isWhitespace(c: u8) bool {
	return for (whitespace) |w| {
		if (c == w) break true;
	} else false;
}