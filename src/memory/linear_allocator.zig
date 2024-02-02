const ft = @import("../ft/ft.zig");

/// LinearAllocator is a basic allocator, it allocate chunks linearly on the space designated by 'buffer'
/// it does not support freeing
pub const LinearAllocator = struct {

	buffer : [*]u8,

	size : usize,

	index : usize = 0,

	locked : bool = false,

	const Self = @This();

	pub const Error = error{NoSpaceLeft, Locked};

	pub fn alloc(self: *Self, comptime T: type, n: usize) Error![]T {
		if (self.locked)
			return Error.Locked;
		if ((@import("std").math.divCeil(usize, @bitSizeOf(T) * (n + 1), 8) catch unreachable) > self.remaining_space()) {
			return Error.NoSpaceLeft;
		}
		self.index += @import("std").mem.alignForward(usize, @intFromPtr(self.buffer) + self.index, @alignOf(T)) - @intFromPtr(self.buffer) + self.index;
		const ret : []T = @as([*]T, @ptrFromInt(@intFromPtr(self.buffer) + self.index))[0..n];
		self.index += (@import("std").math.divCeil(usize, n * @bitSizeOf(T), 8) catch unreachable);
		return ret;
	}

	pub fn free(_: *Self, _: anytype) void {}

	pub fn remaining_space(self: *Self) usize {
		return self.size - self.index;
	}

	pub fn lock(self: *Self) void {
		self.locked = true;
	}

	pub fn upper_bound(self: *Self) usize {
		return @intFromPtr(self.buffer) + self.index;
	}

	pub fn lower_bound(self: *Self) usize {
		return @intFromPtr(self.buffer);
	}
};