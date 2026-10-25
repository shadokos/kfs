const paging = @import("paging.zig");
const logger = @import("std").log.scoped(.page_allocator);

ptr: *anyopaque,
vtable: *const VTable,

pub const VTable = struct {
    alloc_pages: *const fn (ctx: *anyopaque, npages: usize, hint: ?paging.VirtualPagePtr) ?paging.VirtualPagePtr,
    free_pages: *const fn (ctx: *anyopaque, first: paging.VirtualPagePtr, npages: usize) void,
};

const PageAllocator = @This();

pub const Error = error{OutOfMemory};

pub fn alloc_pages(self: PageAllocator, npages: usize) Error!paging.VirtualPagePtr {
    return self.rawAlloc(npages, null) orelse Error.OutOfMemory;
}

pub fn free_pages(self: PageAllocator, first: paging.VirtualPagePtr, npages: usize) void {
    self.rawFree(first, npages);
}

inline fn rawAlloc(self: PageAllocator, npages: usize, hint: ?paging.VirtualPagePtr) ?paging.VirtualPagePtr {
    return self.vtable.alloc_pages(self.ptr, npages, hint);
}

inline fn rawFree(self: PageAllocator, first: paging.VirtualPagePtr, npages: usize) void {
    self.vtable.free_pages(self.ptr, first, npages);
}
