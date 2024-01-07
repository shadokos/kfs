const ft = @import("ft.zig");

pub const ParseIntError = error{ Overflow, InvalidCharacter };

pub fn parseInt(comptime T: type, buf: []const u8, base: u8) ParseIntError!T {
    var index: usize = 0;
    if (buf.len <= index)
        return ParseIntError.InvalidCharacter;

    const is_neg: bool = buf[index] == '-';
    if (buf.len <= index)
        return ParseIntError.InvalidCharacter;

    if (buf[index] == '-' or buf[index] == '+')
        index += 1;

    if (buf.len <= index)
        return ParseIntError.InvalidCharacter;

    if (!ft.ascii.isDigit(buf[index]))
        return ParseIntError.InvalidCharacter;

    const U = ft.meta.Int(@typeInfo(T).Int.signedness, @max(8, @typeInfo(T).Int.bits));
    var ret: U = 0;

    while (index < buf.len) {
        if (!ft.ascii.isDigit(buf[index]))
            return ParseIntError.InvalidCharacter;

        var ov = @mulWithOverflow(ret, @as(U, @intCast(base)));
        if (ov[1] != 0) return ParseIntError.Overflow;

        if (is_neg) {
            ov = @subWithOverflow(ov[0], @as(U, @intCast(charToDigit(buf[index], base) catch return ParseIntError.InvalidCharacter)));
        } else {
            ov = @addWithOverflow(ov[0], @as(U, @intCast(charToDigit(buf[index], base) catch return ParseIntError.InvalidCharacter)));
        }
        if (ov[1] != 0) return ParseIntError.Overflow;

        ret = ov[0];
        index += 1;
    }

    return @as(T, @intCast(ret));
}

test "parseInt" { // stolen from zig's ft lib
	const std = @import("std");
	const math = std.math;
    try std.testing.expect((try parseInt(i32, "-10", 10)) == -10);
    try std.testing.expect((try parseInt(i32, "+10", 10)) == 10);
    try std.testing.expect((try parseInt(u32, "+10", 10)) == 10);
    try std.testing.expectError(error.Overflow, parseInt(u32, "-10", 10));
    try std.testing.expectError(error.InvalidCharacter, parseInt(u32, " 10", 10));
    try std.testing.expectError(error.InvalidCharacter, parseInt(u32, "10 ", 10));
    try std.testing.expectError(error.InvalidCharacter, parseInt(u32, "_10_", 10));
    try std.testing.expectError(error.InvalidCharacter, parseInt(u32, "0x_10_", 10));
    try std.testing.expectError(error.InvalidCharacter, parseInt(u32, "0x10_", 10));
    try std.testing.expectError(error.InvalidCharacter, parseInt(u32, "0x_10", 10));
    try std.testing.expect((try parseInt(u8, "255", 10)) == 255);
    try std.testing.expectError(error.Overflow, parseInt(u8, "256", 10));

    // +0 and -0 should work for unsigned

    try std.testing.expect((try parseInt(u8, "-0", 10)) == 0);
    try std.testing.expect((try parseInt(u8, "+0", 10)) == 0);

    // ensure minInt is parsed correctly

    try std.testing.expect((try parseInt(i1, "-1", 10)) == math.minInt(i1));
    try std.testing.expect((try parseInt(i8, "-128", 10)) == math.minInt(i8));
    try std.testing.expect((try parseInt(i43, "-4398046511104", 10)) == math.minInt(i43));

    // empty string or bare +- is invalid

    try std.testing.expectError(error.InvalidCharacter, parseInt(u32, "", 10));
    try std.testing.expectError(error.InvalidCharacter, parseInt(i32, "", 10));
    try std.testing.expectError(error.InvalidCharacter, parseInt(u32, "+", 10));
    try std.testing.expectError(error.InvalidCharacter, parseInt(i32, "+", 10));
    try std.testing.expectError(error.InvalidCharacter, parseInt(u32, "-", 10));
    try std.testing.expectError(error.InvalidCharacter, parseInt(i32, "-", 10));

    // autodectect the base todo

    // try std.testing.expect((try parseInt(i32, "111", 0)) == 111);
    // try std.testing.expect((try parseInt(i32, "1_1_1", 0)) == 111);
    // try std.testing.expect((try parseInt(i32, "1_1_1", 0)) == 111);
    // try std.testing.expect((try parseInt(i32, "+0b111", 0)) == 7);
    // try std.testing.expect((try parseInt(i32, "+0B111", 0)) == 7);
    // try std.testing.expect((try parseInt(i32, "+0b1_11", 0)) == 7);
    // try std.testing.expect((try parseInt(i32, "+0o111", 0)) == 73);
    // try std.testing.expect((try parseInt(i32, "+0O111", 0)) == 73);
    // try std.testing.expect((try parseInt(i32, "+0o11_1", 0)) == 73);
    // try std.testing.expect((try parseInt(i32, "+0x111", 0)) == 273);
    // try std.testing.expect((try parseInt(i32, "-0b111", 0)) == -7);
    // try std.testing.expect((try parseInt(i32, "-0b11_1", 0)) == -7);
    // try std.testing.expect((try parseInt(i32, "-0o111", 0)) == -73);
    // try std.testing.expect((try parseInt(i32, "-0x111", 0)) == -273);
    // try std.testing.expect((try parseInt(i32, "-0X111", 0)) == -273);
    // try std.testing.expect((try parseInt(i32, "-0x1_11", 0)) == -273);

    // bare binary/octal/decimal prefix is invalid

    // try std.testing.expectError(error.InvalidCharacter, parseInt(u32, "0b", 0));
    // try std.testing.expectError(error.InvalidCharacter, parseInt(u32, "0o", 0));
    // try std.testing.expectError(error.InvalidCharacter, parseInt(u32, "0x", 0));

    // edge cases which previously errored due to base overflowing T

    try std.testing.expectEqual(@as(i2, -2), try parseInt(i2, "-10", 2));
    try std.testing.expectEqual(@as(i4, -8), try parseInt(i4, "-10", 8));
    try std.testing.expectEqual(@as(i5, -16), try parseInt(i5, "-10", 16));
}

pub fn charToDigit(c: u8, base: u8) error{InvalidCharacter}!u8 {
    const ret = switch (c) {
        '0'...'9' => c - '0',
        'a'...'z' => c - 'a' + 10,
        'A'...'Z' => c - 'A' + 10,
        else => return error.InvalidCharacter,
    };
    if (ret >= base)
        return error.InvalidCharacter;
    return ret;
}
