const ft = @import("ft");
const LinearAllocator = @import("linear_allocator.zig").LinearAllocator;

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

        fn vtable_free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
            // const self: *Self = @ptrCast(@alignCast(ctx));
            _ = buf_align;
            _ = ret_addr;
            _ = buf;
            _ = ctx;
        }

        fn vtable_alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
            const self: *Self = @ptrCast(@alignCast(ctx));
            _ = ptr_align;
            _ = ret_addr;
            return @alignCast((self.alloc(u8, len) catch return null).ptr);
        }

        fn vtable_resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
            _ = buf_align;
            _ = ret_addr;
            _ = new_len;
            _ = buf;
            _ = ctx;
            return false;
        }

        const vTable = ft.mem.Allocator.VTable{
            .alloc = &vtable_alloc,
            .resize = &vtable_resize,
            .free = &vtable_free,
        };

        pub fn allocator(self: *Self) ft.mem.Allocator {
            return .{ .ptr = self, .vtable = &vTable };
        }
    };
}
