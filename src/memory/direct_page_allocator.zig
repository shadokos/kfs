const ft = @import("ft");
const paging = @import("paging.zig");
const pageFrameAllocator = &@import("../memory.zig").pageFrameAllocator;
const PageAllocator = @import("page_allocator.zig");
const mapping = @import("mapping.zig");
const logger = @import("ft").log.scoped(.DirectPageAllocator);

pub const DirectPageAllocator = struct {
    mapping_offset: paging.PhysicalPtrDiff,

    const Self = @This();

    pub fn init(_mapping_offset: paging.PhysicalPtrDiff) Self {
        return .{ .mapping_offset = _mapping_offset };
    }

    fn vtable_alloc_pages(ctx: *anyopaque, npages: usize, hint: ?paging.VirtualPagePtr) ?paging.VirtualPagePtr {
        const self: *Self = @ptrCast(@alignCast(ctx));
        if (hint) |_| {
            return null;
        } else {
            const physical = pageFrameAllocator.alloc_pages_zone(.Direct, npages) catch return null;
            return @as(
                paging.VirtualPagePtr,
                @ptrFromInt(
                    @as(usize, @intCast(@as(paging.PhysicalPtrDiff, @intCast(physical)) + self.mapping_offset)),
                ),
            );
        }
    }

    fn vtable_free_pages(ctx: *anyopaque, first: paging.VirtualPagePtr, npages: usize) void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        if (@as(paging.PhysicalPtr, @intFromPtr(first)) < self.mapping_offset) {
            @panic("Invalid ptr passed to DirectPageAllocator.vtable_free_pages");
        }
        return pageFrameAllocator.free_pages(
            @intCast(
                @as(paging.PhysicalPtr, @intFromPtr(first)) - self.mapping_offset,
            ),
            npages,
        ) catch @panic("invalid free_pages"); // todo underflow
    }

    const vTable = PageAllocator.VTable{
        .alloc_pages = &vtable_alloc_pages,
        .free_pages = &vtable_free_pages,
    };

    pub fn page_allocator(self: *Self) PageAllocator {
        return .{ .ptr = self, .vtable = &vTable };
    }
};
