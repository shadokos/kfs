const LinearAllocator = @import("linear_allocator.zig").LinearAllocator;

/// implement LinearAllocator on a statically allocated array
pub fn StaticAllocator(comptime size: usize) type {
    return struct {
        allocator: ?LinearAllocator = null,
        buffer: [size]u8 = undefined,

        const Self = @This();

        const Error = LinearAllocator.Error;

        fn check_init(self: *Self) *LinearAllocator {
            return if (self.allocator) |*a| a else b: {
                self.allocator = LinearAllocator{ .buffer = &self.buffer, .size = size };
                break :b if (self.allocator) |*a| a else unreachable;
            };
        }

        pub fn alloc(self: *Self, comptime T: type, n: usize) Error![]T {
            return self.check_init().alloc(T, n);
        }

        pub fn free(self: *Self, arg: anytype) void {
            return self.check_init().free(arg);
        }

        pub fn remaining_space(self: *Self) usize {
            return self.check_init().remaining_space();
        }

        pub fn upper_bound(self: *Self) usize {
            return self.check_init().upper_bound();
        }

        pub fn lower_bound(self: *Self) usize {
            return self.check_init().lower_bound();
        }

        pub fn lock(self: *Self) void {
            return self.check_init().lock();
        }
    };
}
