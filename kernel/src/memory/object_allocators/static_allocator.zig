const std = @import("std");
const LinearAllocator = @import("linear_allocator.zig").LinearAllocator;
const Alignment = std.mem.Alignment;

/// implement LinearAllocator on a statically allocated array
pub fn StaticAllocator(comptime size: usize) type {
    return struct {
        underlying: ?LinearAllocator = null,
        buffer: [size]u8 = undefined,

        const Self = @This();

        const Error = LinearAllocator.Error;

        fn check_init(self: *Self) *LinearAllocator {
            return if (self.underlying) |*a| a else b: {
                self.underlying = LinearAllocator{ .buffer = &self.buffer, .size = size };
                break :b if (self.underlying) |*a| a else unreachable;
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

        fn vtable_alloc(ctx: *anyopaque, len: usize, alignment: Alignment, ret_addr: usize) ?[*]u8 {
            const self: *Self = @ptrCast(@alignCast(ctx));
            _ = alignment; // TODO: use proper alignment
            _ = ret_addr;
            return @alignCast((self.alloc(u8, len) catch return null).ptr);
        }

        fn vtable_resize(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) bool {
            _ = ctx;
            _ = memory;
            _ = alignment;
            _ = new_len;
            _ = ret_addr;
            return false;
        }

        fn vtable_remap(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
            _ = ctx;
            _ = memory;
            _ = alignment;
            _ = new_len;
            _ = ret_addr;
            // Static allocator doesn't support remapping
            return null;
        }

        fn vtable_free(ctx: *anyopaque, memory: []u8, alignment: Alignment, ret_addr: usize) void {
            _ = ctx;
            _ = memory;
            _ = alignment;
            _ = ret_addr;
            // Static allocator doesn't actually free memory
        }

        const vTable = std.mem.Allocator.VTable{
            .alloc = &vtable_alloc,
            .resize = &vtable_resize,
            .remap = &vtable_remap,
            .free = &vtable_free,
        };

        pub fn allocator(self: *Self) std.mem.Allocator {
            return .{ .ptr = self, .vtable = &vTable };
        }
    };
}
