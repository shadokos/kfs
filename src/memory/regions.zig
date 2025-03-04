const ft = @import("ft");
const paging = @import("paging.zig");
const Cache = @import("object_allocators/slab/cache.zig").Cache;
const memory = @import("../memory.zig");
const globalCache = &memory.globalCache;
const mapping = @import("mapping.zig");
const pageFrameAllocator = &memory.pageFrameAllocator;
const cpu = @import("../cpu.zig");
const logger = ft.log.scoped(.regions);

pub const RegionOperations = struct {
    map: *const fn (region: *Region, address: paging.VirtualPagePtr) void,
    free: *const fn (region: *Region, address: paging.VirtualPagePtr, npage: usize) void,
};

pub const Region = struct {
    begin: usize,
    len: usize,
    operations: *const RegionOperations = undefined,
    data: usize = undefined,

    pub fn map_now(self: *Region) !void {
        for (self.begin..self.begin + self.len) |p| {
            try make_present(@ptrFromInt(p * paging.page_size));
        }
    }
};

pub fn make_present(address: paging.VirtualPagePtr) !void {
    const entry: paging.TableEntry = mapping.get_entry(address);
    if (!entry.is_mapped()) {
        @panic("make_present: entry not mapped");
    }
    if (entry.is_present()) {
        return;
    }
    const region: *Region = @ptrFromInt(@intFromPtr(entry.not_present));
    region.operations.map(region, address);
}

pub const PhysicallyContiguousRegion = struct {
    const operations: RegionOperations = .{
        .map = &map,
        .free = &free,
    };

    pub fn init(region: *Region, offset: paging.PhysicalPtrDiff) void {
        region.operations = &operations;
        const ptr = memory.smallAlloc.allocator().create(paging.PhysicalPtrDiff) catch @panic("todo"); // todo error
        ptr.* = offset;
        region.data = @intFromPtr(ptr);
    }

    pub fn map(region: *Region, address: paging.VirtualPagePtr) void {
        const ptr: *const paging.PhysicalPtrDiff = @ptrFromInt(region.data);
        const present_entry: paging.present_table_entry = .{
            // TODO: Remove
            .owner = .User,
            .writable = true,
            .address_fragment = @truncate(
                @as(paging.PhysicalPtr, @intCast(@intFromPtr(address) + ptr.*)) / paging.page_size,
            ),
        };
        mapping.set_entry(address, .{ .present = present_entry });
        cpu.reload_cr3();
        @memset(address, 0);
    }

    pub fn free(region: *Region, address: paging.VirtualPagePtr, npages: usize) void {
        const physical_ptr = mapping.get_physical_ptr(@ptrCast(address)) catch unreachable; // todo
        memory.pageFrameAllocator.free_pages(physical_ptr, npages) catch @panic("todo2");

        const ptr: *paging.PhysicalPtrDiff = @ptrFromInt(region.data);
        memory.smallAlloc.allocator().destroy(ptr);
    }
};

pub const PhysicalMapping = struct {
    const operations: RegionOperations = .{
        .map = &map,
        .free = &free,
    };

    pub fn init(region: *Region, offset: paging.PhysicalPtrDiff) void {
        region.operations = &operations;
        const ptr = memory.smallAlloc.allocator().create(paging.PhysicalPtrDiff) catch @panic("todo"); // todo error
        ptr.* = offset;
        region.data = @intFromPtr(ptr);
    }

    pub fn map(region: *Region, address: paging.VirtualPagePtr) void {
        const ptr: *const paging.PhysicalPtrDiff = @ptrFromInt(region.data);
        const present_entry: paging.present_table_entry = .{
            // TODO: Remove
            .owner = .User,
            .writable = true,
            .address_fragment = @truncate(
                @as(paging.PhysicalPtr, @intCast(@intFromPtr(address) + ptr.*)) / paging.page_size,
            ),
        };
        mapping.set_entry(address, .{ .present = present_entry });
        cpu.reload_cr3();
    }

    pub fn free(region: *Region, _: paging.VirtualPagePtr, _: usize) void {
        const ptr: *paging.PhysicalPtrDiff = @ptrFromInt(region.data);
        memory.smallAlloc.allocator().destroy(ptr);
    }
};

pub const VirtuallyContiguousRegion = struct {
    const operations: RegionOperations = .{
        .map = &map,
        .free = &free,
    };

    pub fn init(region: *Region) void {
        region.operations = &operations;
    }

    pub fn map(_: *Region, address: paging.VirtualPagePtr) void {
        // const physical = try pageFrameAllocator.alloc_pages(1); // todo
        const physical = pageFrameAllocator.alloc_pages(1) catch @panic("todo");
        const present_entry: paging.present_table_entry = .{
            // TODO: Remove
            .owner = .User,
            .writable = true,
            .address_fragment = @truncate(physical >> 12),
        };
        mapping.set_entry(address, .{ .present = present_entry });
        cpu.reload_cr3();
        @memset(address, 0);
    }

    pub fn free(_: *Region, address: paging.VirtualPagePtr, npages: usize) void {
        const page: usize = @intFromPtr(address) / paging.page_size;
        for (0..npages) |p| // todo overflow (physical can be 64 bit)
        {
            const page_address: paging.VirtualPagePtr = @ptrFromInt((page + p) * paging.page_size);
            const entry = mapping.get_entry(page_address);
            if (mapping.is_page_present(entry)) {
                const physical_ptr = mapping.get_physical_ptr(@ptrCast(page_address)) catch unreachable; //todo
                memory.pageFrameAllocator.free_pages(physical_ptr, 1) catch @panic("todo3");
            }
        }
    }
};
