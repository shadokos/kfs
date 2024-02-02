const ft = @import("ft.zig");

pub fn log2(x: anytype) @TypeOf(x)
{
	switch (@typeInfo(@TypeOf(x))) {
		.Int, .ComptimeInt => {
			var i = 0;
			var absolute = if (x > 0) x else -x;
			while ((absolute >> i) > 1) : (i += 1) {}
			return i;
		},
		else => unreachable // todo
	}
}

pub fn IntFittingRange(comptime from: comptime_int, comptime to: comptime_int) type {
	if (from > to) {
		@compileError("invalid range");
	}
    if (from == 0 and to == 0) {
    	return u0;
    }

	var absolute_max = if (-from > to) -from else to;
    comptime var bits = @max(log2(absolute_max), 1);
    const signedness : @import("std").builtin.Signedness = if (from < 0) .signed else .unsigned;
    return ft.meta.Int(signedness, bits);
}

pub fn abs(comptime T: type, n: T) T {
	return if (n < 0) -n else n;
}

pub fn divCeil(comptime T: type, numerator: T, denominator: T) !T {
	return if (@mod(numerator, denominator) != 0)
		@divFloor(numerator, denominator) + 1
	else
		@divFloor(numerator, denominator);
}