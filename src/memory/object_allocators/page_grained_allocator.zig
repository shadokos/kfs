const ft = @import("../../ft/ft.zig");
const paging = @import("../paging.zig");
const logger = ft.log.scoped(.PageGrainedAllocator);
const PageAllocator = @import("../page_allocator.zig");

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
    pub fn alloc(self: *Self, comptime T: type, n: usize) Error![]T { // todo: specify error
        const npages = ft.math.divCeil(
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

    fn vtable_free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        _ = buf_align; // todo
        _ = ret_addr; // todo
        const chunk: *ChunkHeader = @ptrFromInt(ft.mem.alignForward(
            usize,
            @intFromPtr(buf.ptr) - paging.page_size,
            paging.page_size,
        ));
        // const chunk: *ChunkHeader = @ptrFromInt(@as(usize, @intFromPtr(buf.ptr)) - @sizeOf(ChunkHeader));

        self.pageAllocator.free_pages(@ptrCast(@alignCast(chunk)), chunk.npages);
    }

    fn vtable_alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
        const self: *Self = @ptrCast(@alignCast(ctx));
        _ = ret_addr; // todo
        const alignment: usize = @as(usize, 1) << @intCast(ptr_align);
        if (alignment > paging.page_size)
            return null;
        const npages = ft.math.divCeil(
            usize,
            @sizeOf(ChunkHeader) + len + alignment,
            paging.page_size,
        ) catch unreachable;
        const chunk: *ChunkHeader = @ptrCast(@alignCast(self.pageAllocator.alloc_pages(npages) catch return null));
        chunk.npages = npages;

        return @as([*]u8, @ptrFromInt(ft.mem.alignForward(
            usize,
            @intFromPtr(chunk) + @sizeOf(ChunkHeader),
            alignment,
        )));
    }

    fn vtable_resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
        const self: *Self = @ptrCast(@alignCast(ctx));
        _ = buf_align; // todo
        _ = ret_addr; // todo
        const actual_size = self.obj_size(buf.ptr) catch return false;
        if (new_len <= actual_size) return true;
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
