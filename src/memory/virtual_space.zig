const ft = @import("../ft/ft.zig");
const paging = @import("paging.zig");
const VirtualSpaceAllocator = @import("virtual_space_allocator.zig").VirtualSpaceAllocator;
const mapping = @import("mapping.zig");
const pageFrameAllocator = &@import("../memory.zig").pageFrameAllocator;
const cpu = @import("../cpu.zig");
const Cache = @import("object_allocators/slab/cache.zig").Cache;
const globalCache = &@import("../memory.zig").globalCache;
const logger = ft.log.scoped(.virtual_space);

const Region = @import("regions.zig").Region;
const RegionSet = @import("region_set.zig").RegionSet;

const InterruptFrame = @import("../interrupts.zig").InterruptFrame;

fn page_fault_handler(frame: InterruptFrame) callconv(.C) void {
    const ErrorType = packed struct(u32) {
        present: bool,
        type: enum(u1) {
            Read = 0,
            Write = 1,
        },
        mode: enum(u1) {
            Supervisor = 0,
            User = 1,
        },
        unused: u29 = undefined,
    };
    const error_object: ErrorType = @bitCast(frame.code);
    const address: paging.VirtualPtr = @ptrFromInt(cpu.get_cr2());
    const page_address: paging.VirtualPagePtr = @ptrFromInt(
        ft.mem.alignBackward(usize, cpu.get_cr2(), paging.page_size),
    );
    const entry: paging.TableEntry = mapping.get_entry(page_address);
    if (mapping.is_page_present(entry)) {
        @panic("page fault on a present page! (entry is not invalidated)");
    } else if (mapping.is_page_mapped(entry)) {
        @import("regions.zig").make_present(page_address) catch |e| {
            ft.log.err("PAGE FAULT!\n\tcannot map address 0x{x:0>8}:\n\t{s}", .{
                @intFromPtr(address),
                @errorName(e),
            });
        };
    } else {
        ft.log.err(
            "PAGE FAULT!\n\taddress 0x{x:0>8} is not mapped\n\taction type: {s}\n\tmode: {s}\n\terror: {s}",
            .{
                @intFromPtr(address),
                @tagName(error_object.type),
                @tagName(error_object.mode),
                if (error_object.present) "page-level protection violation" else "page not present",
            },
        );
    }
}

pub const VirtualSpace = struct {
    spaceAllocator: VirtualSpaceAllocator,
    regions: RegionSet = .{},
    directory_region: ?*Region = null,
    directory: mapping.Directory align(4096),
    // active: bool = false,

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
            5,
        );
    }

    pub fn global_init() !void {
        try init_cache();
        try Region.init_cache();
        try VirtualSpaceAllocator.global_init();
    }

    pub fn clone(self: *Self) !*Self {
        // const ret = try cache.allocator().create(Self); todo
        const memory = @import("../memory.zig");
        const ret = try memory.virtualMemory.allocator().create(Self);
        try ret.init();
        ret.spaceAllocator = try self.spaceAllocator.clone();
        ret.regions = try self.regions.clone();
        ret.directory.userspace = self.directory.userspace;

        if (self.directory_region) |dr| {
            ret.directory_region = ret.regions.find(@ptrFromInt(dr.begin << paging.page_bits));
        }

        ret.transfer();

        const directory_region = ret.directory_region orelse @panic("todo");
        try ret.clone_region(directory_region);

        var current = ret.regions.list;
        while (current) |r| : (current = r.next) {
            if (r == directory_region) continue;
            try ret.clone_region(r);
        }
        return ret;
    }

    fn clone_region(self: *Self, region: *Region) !void {
        _ = self; // todo
        for (region.begin..region.begin + region.len) |p| {
            const pagePtr: paging.VirtualPagePtr = @ptrFromInt(p << paging.page_bits);
            var entry = mapping.get_entry(pagePtr);
            if (entry.is_present()) {
                const physical = try pageFrameAllocator.alloc_pages(1);
                errdefer pageFrameAllocator.free_pages(physical, 1) catch unreachable;
                const memory = @import("../memory.zig");
                const virtual = try memory.kernel_virtual_space.map_anywhere(physical, 1);
                defer memory.kernel_virtual_space.unmap(virtual, 1) catch unreachable;
                @memcpy(virtual[0..], pagePtr[0..]);
                entry.present.address_fragment = @intCast(physical >> paging.page_bits);
            } else {
                entry.not_present = @ptrCast(region);
            }
            mapping.set_entry(pagePtr, entry);
        }
    }

    pub fn set_handler() void {
        const interrupts = @import("../interrupts.zig");
        interrupts.set_intr_gate(.PageFault, interrupts.Handler.create(&page_fault_handler, true));
    }

    pub fn add_space(self: *Self, begin: usize, len: usize) !void {
        try self.spaceAllocator.add_space(begin, len);
    }

    /// map a virtual page to a physical page
    pub fn map(self: *Self, physical: paging.PhysicalPtr, virtual: paging.VirtualPagePtr, npages: usize) !void {
        const region = try self.reserve_region(@intFromPtr(virtual) >> 12, npages);
        if (region) |r| {
            r.value = .{
                .physical_mapping = .{
                    .offset = physical - @intFromPtr(virtual),
                },
            };
            self.commit(r, true);
        } else return error.TODO;
    }

    /// unmap a zone previously mapped
    pub fn unmap(self: *Self, virtual_pages: paging.VirtualPagePtr, npages: usize) !void {
        const region = self.find_region(@ptrCast(virtual_pages)) orelse return Error.InvalidPointer;
        const page: usize = @intFromPtr(virtual_pages) / paging.page_size;
        if (region.begin + region.len < page + npages) {
            @panic("todo invalid region 2");
        }
        if (page != region.begin) {
            const left = try self.create_region(region.begin, page - region.begin);
            left.value = region.value;
            self.commit(left, false);
        }
        if (page + npages != region.begin + region.len) {
            const right = try self.create_region(page + npages, region.begin + region.len - (page + npages));
            right.value = region.value;
            switch (right.value) {
                .virtually_contiguous_allocation => {},
                .physically_contiguous_allocation => {},
                .physical_mapping => {},
            }
            self.commit(right, false);
        }
        self.destroy_region(region);
        for (0..npages) |p| {
            const ptr: paging.VirtualPagePtr = @ptrFromInt((page + p) * paging.page_size);
            mapping.set_entry(ptr, .{ .not_mapped = .{} });
        }
        cpu.reload_cr3();
        self.spaceAllocator.free_space(page, npages) catch unreachable;
    }

    /// allocate virtual space and map the area pointed by physical to this space
    pub fn map_anywhere(
        self: *Self,
        physical_pages: paging.PhysicalPtr,
        npages: usize,
    ) !paging.VirtualPagePtr {
        const region = try self.alloc_region(npages);
        region.value = .{
            .physical_mapping = .{
                .offset = (@as(paging.PhysicalPtrDiff, @intCast(physical_pages)) - @as(
                    paging.PhysicalPtrDiff,
                    @intCast(region.begin),
                ) * paging.page_size),
            },
        };
        self.commit(region, true);
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
        const virtual_pages: paging.VirtualPagePtr = @ptrFromInt(ft.mem.alignBackward(
            usize,
            @as(usize, @intFromPtr(virtual)),
            paging.page_size,
        ));

        const npages = (ft.mem.alignForward(
            usize,
            @as(usize, @intFromPtr(virtual)) + n,
            paging.page_size,
        ) - @intFromPtr(virtual_pages)) / paging.page_size;
        return self.unmap(virtual_pages, npages);
    }

    pub fn alloc_pages_opt(
        self: *Self,
        npages: usize,
        options: AllocOptions,
    ) !paging.VirtualPagePtr {
        var region = try self.alloc_region(npages);
        if (options.physically_contiguous) {
            const physical = try pageFrameAllocator.alloc_pages(npages);
            region.value = .{ .physically_contiguous_allocation = .{
                .offset = (@as(paging.PhysicalPtrDiff, @intCast(physical)) - @as(
                    paging.PhysicalPtrDiff,
                    @intCast(region.begin),
                ) * paging.page_size),
            } };
        } else {
            region.value = .{ .virtually_contiguous_allocation = .{} };
        }
        self.commit(region, true);
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
        switch (region.value) {
            .physically_contiguous_allocation => {
                const page_address: paging.VirtualPagePtr = @ptrFromInt(page * paging.page_size);
                const physical_ptr = mapping.get_physical_ptr(@ptrCast(page_address)) catch unreachable; // todo
                @import("../memory.zig").pageFrameAllocator.free_pages(physical_ptr, npages) catch @panic("todo2");
            },
            .virtually_contiguous_allocation => {
                for (0..npages) |p| // todo overflow (physical can be 64 bit)
                {
                    const page_address: paging.VirtualPagePtr = @ptrFromInt((page + p) * paging.page_size);
                    const entry = mapping.get_entry(page_address);
                    if (mapping.is_page_present(entry)) {
                        const physical_ptr = mapping.get_physical_ptr(@ptrCast(page_address)) catch unreachable; //todo
                        @import("../memory.zig").pageFrameAllocator.free_pages(physical_ptr, 1) catch @panic("todo3");
                    }
                }
            },
            else => {
                return Error.InvalidPointer;
            },
        }
        return self.unmap(@ptrFromInt(page * paging.page_size), npages);
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
        var region = try self.reserve_region(begin, len) orelse unreachable;

        self.directory_region = region;

        region.value = .{ .virtually_contiguous_allocation = .{} };
        self.commit(region, false);
        if (map_now) {
            try region.map_now();
        }
        cpu.reload_cr3();
    }

    fn find_region(self: *Self, ptr: paging.VirtualPtr) ?*Region {
        return self.regions.find(ptr);
    }

    fn alloc_region(self: *Self, npages: usize) !*Region {
        const begin = try self.spaceAllocator.alloc_space(npages);
        const ret = try self.create_region(begin, npages);
        return ret;
    }

    fn reserve_region(self: *Self, begin: usize, len: usize) !?*Region {
        self.spaceAllocator.set_used(begin, len) catch |e| switch (e) {
            error.NoSpaceFound => return null,
            else => return e,
        };
        const ret = try self.create_region(begin, len);
        return ret;
    }

    fn commit(self: *Self, region: *Region, hard: bool) void {
        _ = self;
        for (region.begin..region.begin + region.len) |p| {
            const entry = mapping.get_entry(@ptrFromInt(p << 12));
            if (!mapping.is_page_present(entry) or hard) {
                mapping.set_entry(@ptrFromInt(p << 12), .{ .not_present = @ptrCast(region) });
            }
        }
        cpu.reload_cr3();
    }

    fn create_region(self: *Self, begin: usize, len: usize) !*Region {
        return self.regions.create_region(.{ .begin = begin, .len = len });
    }

    fn destroy_region(self: *Self, region: *Region) void {
        self.regions.destroy_region(region) catch @panic("double freed region");
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
