const ft = @import("ft");
const Slab = @import("slab/slab.zig").Slab;
const Cache = @import("slab/cache.zig").Cache;
const PageAllocator = @import("../page_allocator.zig");
const globalCache = &@import("../../memory.zig").globalCache;
const logger = ft.log.scoped(.physical_memory);

pub const MultipoolAllocator = struct {
    const Self = @This();

    caches: [14]*Cache = undefined,

    pub fn init(comptime name: []const u8, page_allocator: PageAllocator) !Self {
        const CacheDescription = struct {
            name: []const u8,
            size: usize,
            order: u5,
        };

        const cache_descriptions: [14]CacheDescription = .{
            .{ .name = "4", .size = 4, .order = 0 },
            .{ .name = "8", .size = 8, .order = 0 },
            .{ .name = "16", .size = 16, .order = 0 },
            .{ .name = "32", .size = 32, .order = 0 },
            .{ .name = "64", .size = 64, .order = 0 },
            .{ .name = "128", .size = 128, .order = 0 },
            .{ .name = "256", .size = 256, .order = 1 },
            .{ .name = "512", .size = 512, .order = 2 },
            .{ .name = "1k", .size = 1024, .order = 3 },
            .{ .name = "2k", .size = 2048, .order = 3 },
            .{ .name = "4k", .size = 4096, .order = 3 },
            .{ .name = "8k", .size = 8192, .order = 4 },
            .{ .name = "16k", .size = 16384, .order = 5 },
            .{ .name = "32k", .size = 32768, .order = 5 },
        };

        var ret: Self = undefined;

        inline for (0..cache_descriptions.len) |i| {
            ret.caches[i] = try globalCache.create(
                name ++ "_" ++ cache_descriptions[i].name,
                page_allocator,
                cache_descriptions[i].size,
                @alignOf(usize),
                cache_descriptions[i].order,
            );
        }

        return ret;
    }

    fn _kmalloc(self: *Self, size: usize) !*align(1) usize {
        return switch (size) {
            0...4 => self.caches[0].alloc_one(),
            5...8 => self.caches[1].alloc_one(),
            9...16 => self.caches[2].alloc_one(),
            17...32 => self.caches[3].alloc_one(),
            33...64 => self.caches[4].alloc_one(),
            65...128 => self.caches[5].alloc_one(),
            129...256 => self.caches[6].alloc_one(),
            257...512 => self.caches[7].alloc_one(),
            513...1024 => self.caches[8].alloc_one(),
            1025...2048 => self.caches[9].alloc_one(),
            2049...4096 => self.caches[10].alloc_one(),
            4097...8192 => self.caches[11].alloc_one(),
            8193...16384 => self.caches[12].alloc_one(),
            16385...32768 => self.caches[13].alloc_one(),
            else => Cache.Error.AllocationFailed,
        };
    }

    pub fn alloc(self: *Self, comptime T: type, n: usize) ![]T {
        return @as([*]T, @ptrFromInt(@intFromPtr(try self._kmalloc(@sizeOf(T) * n))))[0..n];
    }

    pub fn free(_: *Self, ptr: anytype) void {
        globalCache.cache.free(@ptrCast(@alignCast(ptr))) catch |e| switch (e) {
            error.InvalidArgument => logger.warn("freeing invalid pointer {*}", .{ptr}),
            else => @panic(@errorName(e)),
        };
    }

    pub fn realloc(self: *Self, comptime T: type, ptr: [*]T, new_size: usize) ![]T {
        const actual_size = try self.obj_size(ptr);
        if (new_size < actual_size) return ptr[0..new_size];
        var obj = try self.alloc(T, new_size);
        @memcpy(obj[0..actual_size], ptr);
        self.free(ptr);
        return obj;
    }

    pub fn obj_size(_: *Self, ptr: anytype) !usize {
        const pfd = globalCache.cache.get_page_frame_descriptor(@ptrCast(@alignCast(ptr)));
        if (!pfd.flags.slab) return error.InvalidArgument;
        const slab: ?*Slab = if (pfd.next) |slab| @ptrCast(@alignCast(slab)) else null;

        if (slab) |s| {
            return if (s.is_obj_in_slab(@ptrCast(@alignCast(ptr))))
                s.header.cache.size_obj
            else
                error.InvalidArgument;
        } else return error.InvalidArgument;
    }

    fn vtable_free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
        _ = ctx;
        _ = buf_align;
        _ = ret_addr;
        globalCache.cache.free(@ptrCast(@alignCast(buf.ptr))) catch |e| switch (e) {
            error.InvalidArgument => logger.warn("freeing invalid pointer {*}", .{buf.ptr}),
            else => @panic(@errorName(e)),
        };
    }

    fn vtable_alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
        const self: *Self = @alignCast(@ptrCast(ctx));
        _ = ptr_align;
        _ = ret_addr;
        return @as([*]u8, @ptrFromInt(@intFromPtr(self._kmalloc(len) catch |e| {
            logger.debug("{s}", .{@errorName(e)});
            return null;
        })));
    }

    fn vtable_resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
        const self: *Self = @ptrCast(@alignCast(ctx));
        _ = ret_addr;
        _ = buf_align;
        const actual_size = self.obj_size(buf.ptr) catch return false;
        if (new_len < actual_size) return true;
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
