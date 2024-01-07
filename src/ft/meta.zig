const ft = @import("ft.zig");
const std = @import("std");

pub fn Int(comptime signedness: std.builtin.Signedness, comptime bit_count: u16) type {
	return @Type(std.builtin.Type{
		.Int = .{.signedness = signedness, .bits = bit_count},
	});
}