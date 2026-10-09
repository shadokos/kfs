const std = @import("std");

pub fn parse_uuid(str: []const u8) ?u128 {
    var ret: u128 = 0;
    for (str) |c| {
        if (c == '-') continue;
        ret *= 16;
        ret += std.fmt.charToDigit(c, 16) catch return null;
    }
    return ret;
}
