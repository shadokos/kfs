const ft = @import("ft.zig");
const std = @import("std");

pub fn Int(comptime signedness: std.builtin.Signedness, comptime bit_count: u16) type {
    return @Type(std.builtin.Type{
        .Int = .{ .signedness = signedness, .bits = bit_count },
    });
}

pub fn fieldIndex(comptime T: type, comptime name: []const u8) ?comptime_int {
    for (@typeInfo(T).Struct.fields, 0..) |f, i| {
        if (ft.mem.eql(u8, f.name, name))
            return i;
    }
    return null;
}
