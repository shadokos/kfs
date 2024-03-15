const paging = @import("paging.zig");
const ft = @import("../ft/ft.zig");
const printk = @import("../tty/tty.zig").printk;
const VirtualSpaceAllocator = @import("virtual_space_allocator.zig").VirtualSpaceAllocator;
const EarlyVirtualSpaceAllocator = @import("early_virtual_addresses_allocator.zig").EarlyVirtualSpaceAllocator;
const PageFrameAllocator = @import("page_frame_allocator.zig").PageFrameAllocator;
const mapping = @import("mapping.zig");
const memory = @import("../memory.zig").mapping;

pub fn VirtualPageAllocator(comptime PageFrameAllocatorType: type) type {
    return struct {
        /// object used to allocate physical page frame
        pageFrameAllocator: *PageFrameAllocatorType = undefined,
        /// object used to map pages
        mapper: Mapper = .{},
        /// virtual address allocator for user space
        userSpaceAllocator: VirtualSpaceAllocatorType = .{},
        /// early virtual address allocator for user space (used at initialization only)
        earlyUserSpaceAllocator: EarlyVirtualSpaceAllocator = undefined,
        /// whether the page allocator is initialized or not
        initialized: bool = false,

        /// type of allocation
        pub const AllocType = enum { KernelSpace, UserSpace };

        /// allocation options
        pub const AllocOptions = struct {
            type: AllocType = .KernelSpace,
            physically_contiguous: bool = true,
        };

        /// global virtual address allocator for kernel space
        var kernelSpaceAllocator: VirtualSpaceAllocatorType = .{};
        var earlyKernelSpaceAllocator: EarlyVirtualSpaceAllocator = undefined;
        var global_initialized: bool = false;

        /// type of the mapper object
        const Mapper = mapping.MapperT(PageFrameAllocatorType);

        /// type of the virtual address allocator object
        pub const VirtualSpaceAllocatorType = VirtualSpaceAllocator(@This());

        /// Errors that can be returned by this class
        pub const Error = error{DoubleFree};

        const Self = @This();

        pub fn init(
            self: *Self,
            _pageFrameAllocator: *PageFrameAllocatorType,
        ) (PageFrameAllocatorType.Error || VirtualSpaceAllocatorType.Error || Mapper.Error)!void {
            self.pageFrameAllocator = _pageFrameAllocator;

            try self.mapper.init(self.pageFrameAllocator);
            if (!global_initialized) {
                try global_init(self);
            }
            self.earlyUserSpaceAllocator = .{
                .address = 0, // todo
                .size = (paging.low_half / paging.page_size),
            };
            self.userSpaceAllocator = try VirtualSpaceAllocatorType.init(
                self,
                0,
                (paging.low_half / paging.page_size),
            );
            self.initialized = true;
        }

        pub fn global_init(
            _pageAllocator: anytype,
        ) (PageFrameAllocatorType.Error || VirtualSpaceAllocatorType.Error)!void {
            earlyKernelSpaceAllocator = .{
                .address = paging.low_half / paging.page_size,
                .size = paging.kernel_virtual_space_size / paging.page_size,
            };
            kernelSpaceAllocator = try VirtualSpaceAllocatorType.init(
                _pageAllocator,
                paging.low_half / paging.page_size,
                paging.kernel_virtual_space_size / paging.page_size,
            );
            try kernelSpaceAllocator.set_used(
                ft.math.divCeil(
                    usize,
                    paging.low_half,
                    paging.page_size,
                ) catch unreachable,
                ft.math.divCeil(
                    usize,
                    @import("../trampoline.zig").kernel_size,
                    paging.page_size,
                ) catch unreachable,
            );
            for (paging.page_dir_ptr[768..], 768..) |dir_entry, dir_index| {
                if (dir_entry.present) {
                    const table = mapping.get_table_ptr(@truncate(dir_index));
                    for (table[0..], 0..) |table_entry, table_index| {
                        if (table_entry.present) {
                            kernelSpaceAllocator.set_used(@as(u32, @bitCast(paging.VirtualPtrStruct{
                                .page_index = 0,
                                .table_index = @truncate(table_index),
                                .dir_index = @truncate(dir_index),
                            })) >> 12, 1) catch {};
                        }
                    }
                }
            }
            global_initialized = true;
        }

        /// allocate virtual space
        fn alloc_virtual_space(
            self: *Self,
            npages: usize,
            allocType: AllocType,
        ) (PageFrameAllocatorType.Error || VirtualSpaceAllocatorType.Error)!paging.VirtualPagePtr {
            switch (allocType) {
                .UserSpace => {
                    if (self.initialized) {
                        return @ptrFromInt(try self.userSpaceAllocator.alloc_space(npages) * paging.page_size);
                    } else {
                        @setCold(true);
                        return @ptrFromInt(try self.earlyUserSpaceAllocator.alloc_space(npages) * paging.page_size);
                    }
                },
                .KernelSpace => {
                    if (global_initialized) {
                        return @ptrFromInt(try kernelSpaceAllocator.alloc_space(npages) * paging.page_size);
                    } else {
                        @setCold(true);
                        return @ptrFromInt(try earlyKernelSpaceAllocator.alloc_space(npages) * paging.page_size);
                    }
                },
            }
        }

        /// free virtual space
        fn free_virtual_space(
            self: *Self,
            address: paging.VirtualPagePtr,
            npages: usize,
        ) error{ DoubleFree, NoSpaceFound }!void {
            return (b: {
                if (paging.is_user_space(address)) {
                    if (self.initialized) {
                        break :b self.userSpaceAllocator.free_space(
                            @intFromPtr(address) / paging.page_size,
                            npages,
                        );
                    } else {
                        @setCold(true);
                        break :b self.earlyUserSpaceAllocator.free_space(
                            @intFromPtr(address) / paging.page_size,
                            npages,
                        );
                    }
                } else {
                    if (global_initialized) {
                        break :b kernelSpaceAllocator.free_space(
                            @intFromPtr(address) / paging.page_size,
                            npages,
                        );
                    } else {
                        @setCold(true);
                        break :b earlyKernelSpaceAllocator.free_space(
                            @intFromPtr(address) / paging.page_size,
                            npages,
                        );
                    }
                }
            }) catch |e| switch (e) {
                error.DoubleFree, error.NoSpaceFound => |e2| e2,
                else => @panic("can't free virtual space"),
            };
        }

        /// allocate virtual space and map the area pointed by physical to this space
        pub fn map_anywhere(
            self: *Self,
            physical_pages: paging.PhysicalPtr,
            npages: usize,
            allocType: AllocType,
        ) (PageFrameAllocatorType.Error || VirtualSpaceAllocatorType.Error || Mapper.Error)!paging.VirtualPagePtr {
            const virtual = try self.alloc_virtual_space(npages, allocType);

            errdefer self.free_virtual_space(virtual, npages) catch unreachable;

            try self.mapper.map(virtual, physical_pages, npages);
            return virtual;
        }

        /// allocate virtual space and map the area pointed by physical to this space
        pub fn map_object_anywhere(
            self: *Self,
            physical: paging.PhysicalPtr,
            size: usize,
            allocType: AllocType,
        ) (PageFrameAllocatorType.Error || VirtualSpaceAllocatorType.Error || Mapper.Error)!paging.VirtualPtr {
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
            const virtual = try self.map_anywhere(physical_pages, npages, allocType);
            return @ptrFromInt(@intFromPtr(virtual) + physical % paging.page_size);
        }

        /// map a virtual ptr to a physical ptr (all the page is mapped)
        pub fn map(self: *Self, physical: paging.PhysicalPtr, virtual: paging.VirtualPagePtr, npages: usize) !void {
            try self.mapper.map(virtual, physical, npages);
        }

        /// unmap a zone previously mapped
        pub fn unmap(self: *Self, virtual_pages: paging.VirtualPagePtr, npages: usize) !void {
            try self.mapper.unmap(virtual_pages, npages);
            return self.free_virtual_space(virtual_pages, npages);
        }

        /// unmap an object previously mapped
        pub fn unmap_object(self: *Self, virtual: paging.VirtualPtr, n: usize) !void {
            const virtual_pages: paging.VirtualPagePtr = @ptrFromInt(ft.mem.alignBackward(
                usize,
                @as(usize, @intFromPtr(virtual)),
                paging.page_size,
            )); // todo
            const npages = (ft.mem.alignForward(
                usize,
                @as(usize, @intFromPtr(virtual)) + n,
                paging.page_size,
            ) - @intFromPtr(virtual_pages)) / paging.page_size;
            return self.unmap(virtual_pages, npages);
        }

        /// unmap an area without freeing the virtual address space
        pub fn unmap_raw(self: *Self, virtual: paging.VirtualPtr, n: usize) void {
            const virtual_pages: paging.VirtualPagePtr = @ptrFromInt(
                ft.mem.alignBackward(usize, @as(usize, @intFromPtr(virtual)), paging.page_size),
            ); // todo
            const npages = (ft.mem.alignForward(
                usize,
                @as(usize, @intFromPtr(virtual)) + n,
                paging.page_size,
            ) - @intFromPtr(virtual_pages)) / paging.page_size;
            self.mapper.unmap(virtual_pages, npages);
        }

        /// allocate npages pages with options
        pub fn alloc_pages_opt(
            self: *Self,
            npages: usize,
            options: AllocOptions,
        ) (PageFrameAllocatorType.Error || VirtualSpaceAllocatorType.Error)!paging.VirtualPagePtr {
            const virtual = try self.alloc_virtual_space(npages, options.type);

            if (options.physically_contiguous) {
                errdefer self.free_virtual_space(virtual, npages) catch unreachable;
                const physical = try self.pageFrameAllocator.alloc_pages(npages);
                errdefer self.pageFrameAllocator.free_pages(physical, npages) catch unreachable;

                self.mapper.map(virtual, physical, npages) catch unreachable;
            } else {
                for (0..npages) |p| {
                    errdefer self.free_pages(virtual, p) catch {};
                    const physical = try self.pageFrameAllocator.alloc_pages(1);
                    self.mapper.map(@ptrFromInt(
                        @intFromPtr(virtual) + p * paging.page_size,
                    ), physical, 1) catch unreachable;
                }
            }
            return @ptrCast(virtual);
        }

        /// allocate npages pages with default options
        pub fn alloc_pages(
            self: *Self,
            npages: usize,
        ) (PageFrameAllocatorType.Error || VirtualSpaceAllocatorType.Error)!paging.VirtualPagePtr { // todo: ret type
            return self.alloc_pages_opt(npages, .{});
        }

        /// free the `npages` pages at address `address` previously allocated using alloc_pages_opt or alloc_pages
        pub fn free_pages(self: *Self, address: paging.VirtualPagePtr, npages: usize) !void {
            for (0..npages) |p| {
                const virtual: paging.VirtualPagePtr = @ptrFromInt(@intFromPtr(address) + p * paging.page_size);

                const physical = try mapping.get_physical_ptr(@ptrCast(virtual));

                try self.mapper.unmap(virtual, 1);

                try self.pageFrameAllocator.free_pages(physical, 1);
            }
            self.free_virtual_space(address, npages) catch return Error.DoubleFree;
        }

        /// return the page frame descriptor of the page pointed by `address`
        pub fn get_page_frame_descriptor(self: *Self, address: paging.VirtualPagePtr) !*paging.page_frame_descriptor {
            return self.pageFrameAllocator.get_page_frame_descriptor(try mapping.get_physical_ptr(@ptrCast(address)));
        }

        /// print debug infos
        pub fn print(self: *Self) void {
            printk("User space:\n", .{});
            self.userSpaceAllocator.print();
            printk("Kernel space:\n", .{});
            kernelSpaceAllocator.print();
        }
    };
}
