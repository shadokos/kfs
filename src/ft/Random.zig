ptr: *anyopaque,

fillFn: *const fn (*anyopaque, []u8) void,

pub const Xoroshiro128 = @import("Random/Xoroshiro128.zig");

pub const Random = @This();

pub fn init(pointer: anytype, comptime fillFn: fn (@TypeOf(pointer), []u8) void) Random {
	const gen = struct {
		fn fill(ptr: *anyopaque, buf: []u8) void {
			const self : @TypeOf(pointer) = @ptrCast(@alignCast(ptr));
			fillFn(self, buf);
		}
	};
	return Random{.ptr = pointer, .fillFn = gen.fill};
}

pub fn int(r: Random, comptime T: type) T {
	var buf : [@sizeOf(T)]u8 = undefined;
	r.fillFn(r.ptr, &buf);
	return @bitCast(buf);
}

pub fn boolean(r: Random) bool {
	var ret = int(r, u8);
	return (@popCount(ret) % 2) == 1;
}

pub fn bytes(r: Random, buf: []u8) void {
	r.fillFn(r.ptr, buf);
}

// pub inline fn enumValue(r: Random, comptime EnumType: type) EnumType
// fn enumValueWithIndex(r: Random, comptime EnumType: type, comptime Index: type) EnumType
// fn float(r: Random, comptime T: type) T
// fn floatExp(r: Random, comptime T: type) T
// fn floatNorm(r: Random, comptime T: type) T


pub fn intRangeAtMost(r: Random, comptime T: type, at_least: T, at_most: T) T {
	return r.intRangeLessThan(T, at_least, at_most + 1); // todo un peu chelou ca
}

// fn intRangeAtMostBiased(r: Random, comptime T: type, at_least: T, at_most: T) T

pub fn intRangeLessThan(r: Random, comptime T: type, at_least: T, less_than: T) T {
	return r.int(T) % (less_than - at_least) + at_least; // todo ca aussi la
}

// fn intRangeLessThanBiased(r: Random, comptime T: type, at_least: T, less_than: T) T

// fn limitRangeBiased(comptime T: type, random_int: T, less_than: T) T

// inline fn shuffle(r: Random, comptime T: type, buf: []T) void

// fn shuffleWithIndex(r: Random, comptime T: type, buf: []T, comptime Index: type) void

// fn uintAtMost(r: Random, comptime T: type, at_most: T) T

// fn uintAtMostBiased(r: Random, comptime T: type, at_most: T) T

// fn uintLessThan(r: Random, comptime T: type, less_than: T) T

// fn uintLessThanBiased(r: Random, comptime T: type, less_than: T) T

// fn weightedIndex(r: Random, comptime T: type, proportions: []const T) usize

