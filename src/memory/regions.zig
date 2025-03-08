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
    open: *const fn (region: *Region) void,
    split: *const fn (region: *Region) void,
    close: *const fn (region: *Region) void,
    nopage: *const fn (region: *Region, address: paging.VirtualPagePtr) void,
};

pub const Region = struct {
    begin: usize = 0,
    len: usize = 0,

    flags: Flags = .{},

    operations: *const RegionOperations = undefined,
    data: usize = undefined,

    pub const Flags = struct {
        write: bool = false,
        read: bool = false,
        may_write: bool = false,
        may_read: bool = false,
    };

    pub fn map_now(self: *Region) !void {
        for (self.begin..self.begin + self.len) |p| {
            try make_present(@ptrFromInt(p * paging.page_size));
        }
    }

    pub fn unmap(self: *Region) void {
        for (self.begin..self.begin + self.len) |page| {
            mapping.set_entry(
                @ptrFromInt(page * paging.page_size),
                .{ .not_mapped = .{} },
            );
        }
        cpu.reload_cr3();
    }

    pub fn reset_pages(self: *Region, virtual_page: paging.VirtualPagePtr, npage: usize) void {
        const first_page: usize = @as(usize, @intFromPtr(virtual_page)) / paging.page_size;
        for (first_page..first_page + npage) |page| {
            mapping.set_entry(
                @ptrFromInt(page * paging.page_size),
                .{ .not_present = @ptrCast(self) },
            );
        }
        cpu.reload_cr3();
    }

    pub fn set_page(self: *Region, virtual_page: paging.VirtualPagePtr, physical: paging.PhysicalPtr) void {
        const present_entry: paging.present_table_entry = .{
            // TODO: Remove
            .owner = if (self.flags.read or self.flags.write) .User else .Supervisor,
            .writable = self.flags.write,
            .address_fragment = @truncate(physical >> 12),
        };
        mapping.set_entry(virtual_page, .{ .present = present_entry });
        cpu.reload_cr3();
    }

    fn flush_pages(self: *Region, virtual_page: paging.VirtualPagePtr, npage: usize) void {
        const first_page: usize = @as(usize, @intFromPtr(virtual_page)) / paging.page_size;
        for (first_page..first_page + npage) |page| {
            const entry = mapping.get_entry(@ptrFromInt(page * paging.page_size));
            if (mapping.is_page_present(entry)) {
                var present_entry = entry.present;
                present_entry.owner = if (self.flags.read or self.flags.write) .User else .Supervisor;
                present_entry.writable = self.flags.write;
                mapping.set_entry(
                    @ptrFromInt(page * paging.page_size),
                    .{ .present = present_entry },
                );
            } else {
                mapping.set_entry(
                    @ptrFromInt(page * paging.page_size),
                    .{ .not_present = @ptrCast(self) },
                );
            }
        }
        cpu.reload_cr3();
    }

    pub fn flush_page(self: *Region, virtual_page: paging.VirtualPagePtr) void {
        self.flush_pages(virtual_page, 1);
    }

    pub fn flush(self: *Region) void {
        self.flush_pages(@ptrFromInt(self.begin * paging.page_size), self.len);
    }

    pub fn reset(self: *Region) void {
        self.reset_pages(@ptrFromInt(self.begin * paging.page_size), self.len);
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
    region.operations.nopage(region, address);
}

pub const PhysicallyContiguousRegion = struct {
    const operations: RegionOperations = .{
        .open = &open,
        .split = &split,
        .nopage = &nopage,
        .close = &close,
    };

    pub fn init(region: *Region, offset: paging.PhysicalPtrDiff) void {
        region.operations = &operations;
        const ptr = memory.smallAlloc.allocator().create(paging.PhysicalPtrDiff) catch @panic("todo"); // todo error
        ptr.* = offset;
        region.data = @intFromPtr(ptr);
    }

    pub fn open(region: *Region) void {
        const ptr = memory.smallAlloc.allocator().create(paging.PhysicalPtrDiff) catch @panic("todo"); // todo error
        errdefer memory.smallAlloc.allocator().destroy(ptr);
        const physical = pageFrameAllocator.alloc_pages(region.len) catch @panic("todo");
        ptr.* = @as(paging.PhysicalPtrDiff, @intCast(physical)) -
            @as(paging.PhysicalPtrDiff, region.begin);
        region.data = @intFromPtr(ptr);
    }

    pub fn split(region: *Region) void {
        const ptr: *paging.PhysicalPtrDiff = @ptrFromInt(region.data);
        const new_ptr: *paging.PhysicalPtrDiff = memory.smallAlloc.allocator().create(
            paging.PhysicalPtrDiff,
        ) catch @panic("todo");
        new_ptr.* = ptr.*;
        region.data = @intFromPtr(new_ptr);
    }

    pub fn nopage(region: *Region, address: paging.VirtualPagePtr) void {
        const ptr: *const paging.PhysicalPtrDiff = @ptrFromInt(region.data);
        region.set_page(address, @as(paging.PhysicalPtr, @intCast(@intFromPtr(address) + ptr.*)));
        @memset(address, 0);
    }

    pub fn close(region: *Region) void {
        const physical_ptr = mapping.get_physical_ptr(
            @ptrFromInt(region.begin * paging.page_size),
        ) catch unreachable; // todo
        memory.pageFrameAllocator.free_pages(physical_ptr, region.len) catch @panic("todo2");

        const ptr: *paging.PhysicalPtrDiff = @ptrFromInt(region.data);
        memory.smallAlloc.allocator().destroy(ptr);
    }
};

pub const PhysicalMapping = struct {
    const operations: RegionOperations = .{
        .open = &open,
        .split = &split,
        .nopage = &nopage,
        .close = &close,
    };

    pub fn init(region: *Region, offset: paging.PhysicalPtrDiff) void {
        region.operations = &operations;
        const ptr = memory.smallAlloc.allocator().create(paging.PhysicalPtrDiff) catch @panic("todo"); // todo error
        ptr.* = offset;
        region.data = @intFromPtr(ptr);
    }

    pub fn open(_: *Region) void {}

    pub fn split(region: *Region) void {
        const ptr: *paging.PhysicalPtrDiff = @ptrFromInt(region.data);
        const new_ptr: *paging.PhysicalPtrDiff = memory.smallAlloc.allocator().create(
            paging.PhysicalPtrDiff,
        ) catch @panic("todo");
        new_ptr.* = ptr.*;
        region.data = @intFromPtr(new_ptr);
    }

    pub fn nopage(region: *Region, address: paging.VirtualPagePtr) void {
        const ptr: *const paging.PhysicalPtrDiff = @ptrFromInt(region.data);
        region.set_page(address, @as(paging.PhysicalPtr, @intCast(@intFromPtr(address) + ptr.*)));
    }

    pub fn close(region: *Region) void {
        const ptr: *paging.PhysicalPtrDiff = @ptrFromInt(region.data);
        memory.smallAlloc.allocator().destroy(ptr);
    }
};

pub const VirtuallyContiguousRegion = struct {
    const operations: RegionOperations = .{
        .open = &open,
        .split = &split,
        .nopage = &nopage,
        .close = &close,
    };

    pub const Flags = packed struct(u32) {
        private: bool = true,
        unused: u31 = undefined,
    };

    pub fn init(region: *Region, flags: Flags) void {
        region.operations = &operations;
        region.data = @bitCast(flags);
    }

    pub fn open(_: *Region) void {}

    pub fn split(_: *Region) void {}

    pub fn nopage(region: *Region, address: paging.VirtualPagePtr) void {
        // const physical = try pageFrameAllocator.alloc_pages(1); // todo
        const physical = pageFrameAllocator.alloc_pages(1) catch @panic("todo");
        region.set_page(address, physical);
        @memset(address, 0);
    }

    pub fn close(region: *Region) void {
        const page: usize = region.begin;
        for (0..region.len) |p| // todo overflow (physical can be 64 bit)
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
