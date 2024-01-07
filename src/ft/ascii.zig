const ft = @import("ft.zig");

pub fn isDigit(c: u8) bool {
	return c >= '0' and c <= '9';
}