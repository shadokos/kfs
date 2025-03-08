const ft = @import("ft");
const paging = @import("paging.zig");
const VirtualSpaceAllocator = @import("virtual_space_allocator.zig").VirtualSpaceAllocator;
const mapping = @import("mapping.zig");
const pageFrameAllocator = &@import("../memory.zig").pageFrameAllocator;
const cpu = @import("../cpu.zig");
const Cache = @import("object_allocators/slab/cache.zig").Cache;
const globalCache = &@import("../memory.zig").globalCache;

const regions = @import("regions.zig");
const Region = regions.Region;
const RegionSet = @import("region_set.zig").RegionSet;

pub const VirtualSpace = struct {
    spaceAllocator: VirtualSpaceAllocator,
    regions: RegionSet = .{},
    directory_region: ?*Region = null,
    directory: mapping.Directory align(4096),

    pub const Error = error{
        InvalidPointer,
    };

    /// allocation options
    pub const AllocOptions = struct {
        physically_contiguous: bool = true,
        immediate_mapping: bool = false,
    };

    pub var cache: *Cache = undefined;
    const Self = @This();

    pub fn init(self: *Self) !void {
        self.* = Self{
            .spaceAllocator = .{},
            .directory = .{},
        };
        self.copy_kernel_space_tables();
        self.map_directory();
    }

    pub fn init_cache() !void {
        cache = try globalCache.create(
            "VirtualSpace",
            @import("../memory.zig").virtually_contiguous_page_allocator.page_allocator(),
            @sizeOf(Self),
            @alignOf(Self),
            5,
        );
    }

    pub fn global_init() !void {
        try init_cache();
        try RegionSet.init_cache();
        try VirtualSpaceAllocator.global_init();
    }

    pub fn clone(self: *Self) !*Self {
        const ret = try cache.allocator().create(Self);
        try ret.init();
        ret.spaceAllocator = try self.spaceAllocator.clone();
        ret.regions = try self.regions.clone();
        ret.directory.userspace = self.directory.userspace;

        if (self.directory_region) |dr| {
            ret.directory_region = ret.regions.find(dr.begin);
        }

        ret.transfer();
        defer self.transfer();

        const directory_region = ret.directory_region orelse @panic("todo");
        try ret.clone_region(directory_region);

        var current = ret.regions.list.first;
        while (current) |r| : (current = r.next) {
            if (&r.data == directory_region) continue;
            try ret.clone_region(&r.data);
        }
        return ret;
    }

    fn clone_region(self: *Self, region: *Region) !void {
        _ = self; // todo: maybe stateless (can we do this operation while this virtual space is not active)
        for (region.begin..region.begin + region.len) |p| {
            const pagePtr: paging.VirtualPagePtr = @ptrFromInt(p << paging.page_bits);
            var entry = mapping.get_entry(pagePtr);
            if (entry.is_present()) {
                const physical = try pageFrameAllocator.alloc_pages(1);
                errdefer pageFrameAllocator.free_pages(physical, 1) catch unreachable;
                const memory = @import("../memory.zig");
                const virtual = try memory.kernel_virtual_space.map_anywhere(physical, 1);
                defer memory.kernel_virtual_space.unmap(
                    @as(usize, @intFromPtr(virtual)) / paging.page_size,
                    1,
                ) catch unreachable;
                @memcpy(virtual[0..], pagePtr[0..]);
                entry.present.address_fragment = @intCast(physical >> paging.page_bits);
            } else {
                entry.not_present = @ptrCast(region);
            }
            mapping.set_entry(pagePtr, entry);
        }
    }

    pub fn add_space(self: *Self, begin: usize, len: usize) !void {
        try self.spaceAllocator.add_space(begin, len);
    }

    /// map a virtual page to a physical page
    pub fn map(self: *Self, physical: paging.PhysicalPtr, virtual: paging.VirtualPagePtr, npages: usize) !void {
        const region = try RegionSet.create_region();
        errdefer RegionSet.destroy_region(region) catch unreachable;
        regions.PhysicalMapping.init(region, physical - @intFromPtr(virtual));
        try self.add_region_at(region, @intFromPtr(virtual) >> 12, npages, false);
    }

    /// split a region and return the newly allocated right part
    fn split_region(self: *Self, region: *Region, page: usize) Cache.AllocError!*Region {
        if (page <= region.begin or page >= region.begin + region.len) {
            @panic("todo");
        }
        const ret_len = region.begin + region.len - page;
        const ret = try RegionSet.create_region();
        ret.operations = region.operations;
        ret.data = region.data;
        ret.flags = region.flags;
        ret.begin = page;
        ret.len = ret_len;
        region.len -= ret_len;
        ret.operations.split(ret);
        self.regions.add_region(ret);
        ret.flush();

        return ret;
    }

    /// isolate a part of a region by splitting the region zero, one or two times
    pub fn isolate_region(self: *Self, region: *Region, first_page: usize, npage: usize) Cache.AllocError!*Region {
        var ret = region;
        if (first_page + npage < ret.begin + ret.len) {
            _ = try self.split_region(ret, first_page + npage);
        }
        if (first_page > ret.begin) {
            ret = try self.split_region(ret, first_page);
        }
        return ret;
    }

    /// unmap a zone previously mapped
    pub fn unmap(self: *Self, first_page: usize, npage: usize) !void {
        while (self.regions.find_any_in_range(first_page, npage)) |region| {
            self.close_region(try self.isolate_region(region, first_page, npage));
        }
    }

    /// allocate virtual space and map the area pointed by physical to this space
    pub fn map_anywhere(
        self: *Self,
        physical_pages: paging.PhysicalPtr,
        npages: usize,
    ) !paging.VirtualPagePtr {
        const region = try RegionSet.create_region();
        errdefer RegionSet.destroy_region(region) catch unreachable;
        try self.add_region(region, npages);
        regions.PhysicalMapping.init(
            region,
            @as(paging.PhysicalPtrDiff, @intCast(physical_pages)) - @as(
                paging.PhysicalPtrDiff,
                @intCast(region.begin),
            ) * paging.page_size,
        );
        return @ptrFromInt(region.begin << 12);
    }

    /// allocate virtual space and map the area pointed by physical to this space
    pub fn map_object_anywhere(
        self: *Self,
        physical: paging.PhysicalPtr,
        size: usize,
    ) !paging.VirtualPtr {
        const physical_pages = ft.mem.alignBackward(
            paging.PhysicalPtr,
            physical,
            paging.page_size,
        );
        const npages = (ft.mem.alignForward(
            paging.PhysicalPtr,
            physical + size,
            paging.page_size,
        ) - physical_pages) / paging.page_size;
        const virtual = try self.map_anywhere(physical_pages, npages);
        return @ptrFromInt(@intFromPtr(virtual) + physical % paging.page_size);
    }

    /// unmap an object previously mapped
    pub fn unmap_object(self: *Self, virtual: paging.VirtualPtr, n: usize) !void {
        const first_page: usize = @as(usize, @intFromPtr(virtual)) / paging.page_size;

        const npage = ft.math.divCeil(
            usize,
            @as(usize, @intFromPtr(virtual)) % paging.page_size + n,
            paging.page_size,
        ) catch unreachable;

        return self.unmap(first_page, npage);
    }

    pub fn alloc_pages_opt(
        self: *Self,
        npages: usize,
        options: AllocOptions,
    ) !paging.VirtualPagePtr {
        var region = try RegionSet.create_region();
        errdefer RegionSet.destroy_region(region) catch unreachable;
        try self.add_region(region, npages);
        if (options.physically_contiguous) {
            const physical = try pageFrameAllocator.alloc_pages(npages);
            regions.PhysicallyContiguousRegion.init(region, @as(paging.PhysicalPtrDiff, @intCast(physical)) - @as(
                paging.PhysicalPtrDiff,
                @intCast(region.begin),
            ) * paging.page_size);
        } else {
            regions.VirtuallyContiguousRegion.init(region, .{});
        }
        if (options.immediate_mapping) {
            try region.map_now();
        }
        return @ptrFromInt(region.begin << 12);
    }

    /// allocate npages pages with default options
    pub fn alloc_pages(
        self: *Self,
        npages: usize,
    ) !paging.VirtualPagePtr {
        return self.alloc_pages_opt(npages, .{});
    }

    pub fn free_pages(self: *Self, address: paging.VirtualPagePtr, npages: usize) !void {
        const region = self.find_region(@ptrCast(address)) orelse return Error.InvalidPointer;
        const page: usize = @intFromPtr(address) / paging.page_size;
        if (region.begin + region.len < page + npages) {
            return Error.InvalidPointer;
        }
        return self.unmap(page, npages);
    }

    pub fn make_present(address: paging.VirtualPagePtr, npages: usize) !void {
        for (0..npages) |p| {
            try @import("regions.zig").make_present(@ptrFromInt(@intFromPtr(address) + (p * paging.page_size)));
        }
    }

    fn copy_kernel_space_tables(self: *Self) void {
        @memcpy(self.directory._kernelspace[0..], paging.page_dir_ptr[768..1023]);
    }

    fn map_directory(self: *Self) void {
        self.directory.directory = .{
            .present = .{
                .owner = .Supervisor,
                .address_fragment = @truncate(
                    (mapping.get_physical_ptr(@ptrCast(&self.directory)) catch unreachable) >> 12,
                ),
            },
        };
    }

    pub fn fill_page_tables(self: *Self, begin: usize, len: usize, map_now: bool) !void {
        const region = try RegionSet.create_region();
        errdefer RegionSet.destroy_region(region) catch unreachable;

        region.flags = .{
            .read = true,
            .write = true,
            .may_read = true,
            .may_write = true,
        };

        regions.VirtuallyContiguousRegion.init(region, .{});

        self.directory_region = region;

        self.add_region_at(region, begin, len, false) catch unreachable;

        region.flush();

        if (map_now) {
            try region.map_now();
        }
    }

    pub fn find_region(self: *Self, ptr: paging.VirtualPtr) ?*Region {
        return self.regions.find(@intFromPtr(ptr) / paging.page_size);
    }

    pub fn add_region_at(self: *Self, region: *Region, first_page: usize, npages: usize, replace: bool) !void {
        if (self.spaceAllocator.set_used(first_page, npages)) |_| {
            region.begin = first_page;
            region.len = npages;
            region.operations.open(region);
            self.regions.add_region(region);
            region.flush();
        } else |e| {
            if (replace) {
                self.unmap(first_page, npages) catch @panic("todo");
                return self.add_region_at(region, first_page, npages, replace);
            } else {
                return e;
            }
        }
    }

    pub fn add_region(self: *Self, region: *Region, npages: usize) !void {
        region.begin = try self.spaceAllocator.alloc_space(npages);
        region.len = npages;
        self.regions.add_region(region);
        region.flush();
    }

    fn close_region(self: *Self, region: *Region) void {
        region.operations.close(region);

        region.unmap();

        self.regions.remove_region(region);

        self.spaceAllocator.free_space(region.begin, region.len) catch unreachable;

        RegionSet.destroy_region(region) catch @panic("double freed region");
    }

    pub fn generate_page_allocator(self: *Self, _options: AllocOptions) PageAllocatorWithOpt {
        return PageAllocatorWithOpt.init(self, _options);
    }

    pub fn transfer(self: *Self) void {
        mapping.transfer(@ptrCast(&self.directory));
    }
};

const PageAllocator = @import("page_allocator.zig");
const PageAllocatorWithOpt = struct {
    options: AllocOptions = .{},
    virtualSpace: *VirtualSpace,

    const AllocOptions = VirtualSpace.AllocOptions;

    const Self = @This();

    pub fn init(_virtualSpace: *VirtualSpace, _options: AllocOptions) Self {
        return Self{
            .options = _options,
            .virtualSpace = _virtualSpace,
        };
    }

    fn vtable_alloc_pages(ctx: *anyopaque, npages: usize, hint: ?paging.VirtualPagePtr) ?paging.VirtualPagePtr {
        const self: *Self = @ptrCast(@alignCast(ctx));

        if (hint) |_| {
            return null;
        } else {
            return self.virtualSpace.alloc_pages_opt(npages, self.options) catch null;
        }
    }

    fn vtable_free_pages(ctx: *anyopaque, first: paging.VirtualPagePtr, npages: usize) void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        return self.virtualSpace.free_pages(first, npages) catch @panic("invalid free_pages");
    }

    const vTable = PageAllocator.VTable{
        .alloc_pages = &vtable_alloc_pages,
        .free_pages = &vtable_free_pages,
    };

    pub fn page_allocator(self: *Self) PageAllocator {
        return .{ .ptr = self, .vtable = &vTable };
    }
};
