const ft = @import("../ft/ft.zig");
const paging = @import("paging.zig");
const Cache = @import("object_allocators/slab/cache.zig").Cache;
const globalCache = &@import("../memory.zig").globalCache;
const mapping = @import("mapping.zig");
const pageFrameAllocator = &@import("../memory.zig").pageFrameAllocator;
const cpu = @import("../cpu.zig");
const logger = ft.log.scoped(.regions);

pub const Region = struct {
    prev: ?*@This() = null,
    next: ?*@This() = null,
    begin: usize,
    len: usize,
    value: union(enum) {
        virtually_contiguous_allocation: struct {},
        physically_contiguous_allocation: struct {
            offset: paging.PhysicalPtrDiff,
        },
        physical_mapping: struct {
            offset: paging.PhysicalPtrDiff,
        },
    } = undefined,

    pub var cache: ?*Cache = null;
    pub fn init_cache() !void {
        cache = try globalCache.create(
            "regions",
            @import("../memory.zig").directPageAllocator.page_allocator(),
            @sizeOf(@This()),
            4,
        );
    }

    pub fn create() !*Region {
        if (cache) |c| {
            return @ptrCast(try c.alloc_one());
        } else {
            @panic("region cache is not initialized");
        }
    }

    pub fn destroy(r: *Region) !void {
        if (cache) |c| {
            return c.free(@ptrCast(r));
        } else {
            @panic("region cache is not initialized");
        }
    }

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
    switch (region.value) {
        .virtually_contiguous_allocation => {
            const physical = try pageFrameAllocator.alloc_pages(1);
            const present_entry: paging.present_table_entry = .{
                // TODO: remove it
                .owner = .User,
                .writable = true,
                .address_fragment = @truncate(physical >> 12),
            };
            mapping.set_entry(address, .{ .present = present_entry });
            cpu.reload_cr3();
            @memset(address, 0);
        },
        .physically_contiguous_allocation => |m| {
            const present_entry: paging.present_table_entry = .{
                // TODO: remove it
                .owner = .User,
                .writable = true,
                .address_fragment = @truncate(
                    @as(paging.PhysicalPtr, @intCast(@intFromPtr(address) + m.offset)) / paging.page_size,
                ),
            };
            mapping.set_entry(address, .{ .present = present_entry });
            cpu.reload_cr3();
            @memset(address, 0);
        },
        .physical_mapping => |m| {
            const present_entry: paging.present_table_entry = .{
                // TODO: remove it
                .owner = .User,
                .writable = true,
                .address_fragment = @truncate(
                    @as(paging.PhysicalPtr, @intCast(@intFromPtr(address) + m.offset)) / paging.page_size,
                ),
            };
            mapping.set_entry(address, .{ .present = present_entry });
            cpu.reload_cr3();
        },
    }
}
