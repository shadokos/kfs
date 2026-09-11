const std = @import("std");
const paging = @import("../paging.zig");
const PageAllocator = @import("../page_allocator.zig");
const Alignment = std.mem.Alignment;

const logger = std.log.scoped(.PageGrainedAllocator);

/// allocator that allocate one object by page
pub const PageGrainedAllocator = struct {
    /// underlying page allocator
    pageAllocator: PageAllocator,

    /// header of a chunk
    const ChunkHeader = packed struct {
        npages: usize,
    };

    pub const Error = PageAllocator.Error;

    const Self = @This();

    /// init the allocator
    pub fn init(_pageAllocator: PageAllocator) Self {
        const self = Self{ .pageAllocator = _pageAllocator };
        return self;
    }

    /// allocate virtually contiguous memory
    pub fn alloc(self: *Self, comptime T: type, n: usize) Error![]T {
        const npages = std.math.divCeil(
            usize,
            @sizeOf(ChunkHeader) + @sizeOf(T) * n,
            paging.page_size,
        ) catch unreachable;
        const chunk: *ChunkHeader = @ptrCast(@alignCast(try self.pageAllocator.alloc_pages(npages)));
        chunk.npages = npages;

        return @as([*]T, @ptrFromInt(@intFromPtr(chunk) + @sizeOf(ChunkHeader)))[0..n];
    }

    /// free memory previously allocated with alloc()
    pub fn free(self: *Self, arg: anytype) void {
        const chunk: *ChunkHeader = @ptrFromInt(@as(usize, @intFromPtr(arg)) - @sizeOf(ChunkHeader));

        self.pageAllocator.free_pages(@ptrCast(@alignCast(chunk)), chunk.npages);
    }

    /// return the size of an object
    pub fn obj_size(_: *Self, ptr: anytype) !usize {
        const chunk: *ChunkHeader = @ptrFromInt(@as(usize, @intFromPtr(ptr)) - @sizeOf(ChunkHeader));
        return (chunk.npages * paging.page_size - @sizeOf(ChunkHeader));
    }

    fn vtable_alloc(ctx: *anyopaque, len: usize, alignment: Alignment, ret_addr: usize) ?[*]u8 {
        const self: *Self = @ptrCast(@alignCast(ctx));
        _ = ret_addr;
        const alignment_bytes = alignment.toByteUnits();
        if (alignment_bytes > paging.page_size)
            return null;
        const npages = std.math.divCeil(
            usize,
            @sizeOf(ChunkHeader) + len + alignment_bytes,
            paging.page_size,
        ) catch unreachable;
        const chunk: *ChunkHeader = @ptrCast(@alignCast(self.pageAllocator.alloc_pages(npages) catch return null));
        chunk.npages = npages;

        return @as([*]u8, @ptrFromInt(std.mem.alignForward(
            usize,
            @intFromPtr(chunk) + @sizeOf(ChunkHeader),
            alignment_bytes,
        )));
    }

    fn vtable_resize(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *Self = @ptrCast(@alignCast(ctx));
        _ = alignment;
        _ = ret_addr;
        const actual_size = self.obj_size(memory.ptr) catch return false;
        if (new_len <= actual_size) return true;
        return false;
    }

    fn vtable_remap(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        _ = ctx;
        _ = memory;
        _ = alignment;
        _ = new_len;
        _ = ret_addr;
        // Page-grained allocator doesn't support remapping
        return null;
    }

    fn vtable_free(ctx: *anyopaque, memory: []u8, alignment: Alignment, ret_addr: usize) void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        _ = alignment;
        _ = ret_addr;
        const chunk: *ChunkHeader = @ptrFromInt(std.mem.alignForward(
            usize,
            @intFromPtr(memory.ptr) - paging.page_size,
            paging.page_size,
        ));

        self.pageAllocator.free_pages(@ptrCast(@alignCast(chunk)), chunk.npages);
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
