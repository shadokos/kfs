const paging = @import("paging.zig");
const ft = @import("../ft/ft.zig");
const printk = @import("../tty/tty.zig").printk;
const VirtualAddressesAllocator = @import("virtual_addresses_allocator.zig").VirtualAddressesAllocator;
const EarlyVirtualAddressesAllocator = @import("early_virtual_addresses_allocator.zig").EarlyVirtualAddressesAllocator;
const PageFrameAllocator = @import("page_frame_allocator.zig").PageFrameAllocator;
const mapping = @import("mapping.zig");
const memory = @import("../memory.zig").mapping;

pub fn VirtualPageAllocator(comptime PageFrameAllocatorType : type) type {
	return struct {
		/// object used to allocate physical page frame
		pageFrameAllocator : *PageFrameAllocatorType = undefined,
		/// object used to map pages
		mapper : Mapper = .{},
		/// virtual address allocator for user space
		userAddressesAllocator : VirtualAddressesAllocatorType = .{},
		/// early virtual address allocator for user space (used at initialization only)
		earlyUserAddressesAllocator : EarlyVirtualAddressesAllocator = undefined,
		/// whether the page allocator is initialized or not
		initialized : bool = false,

		/// type of allocation
		pub const AllocType = enum {
			KernelSpace,
			UserSpace
		};

		/// allocation options
		pub const AllocOptions = struct {
			type : AllocType = .KernelSpace,
			physically_contiguous : bool = true,
		};

		/// global virtual address allocator for kernel space
		var kernelAddressesAllocator : VirtualAddressesAllocatorType = .{};
		var earlyKernelAddressesAllocator : EarlyVirtualAddressesAllocator = undefined;
		var global_initialized : bool = false;

		/// type of the mapper object
		const Mapper = mapping.MapperT(PageFrameAllocatorType);

		/// type of the virtual address allocator object
		pub const VirtualAddressesAllocatorType = VirtualAddressesAllocator(@This());

		/// Errors that can be returned by this class
		pub const Error = error{DoubleFree};

		const Self = @This();

		pub fn init(self : *Self, _pageFrameAllocator : *PageFrameAllocatorType) (PageFrameAllocatorType.Error || VirtualAddressesAllocatorType.Error || Mapper.Error)!void {
			self.pageFrameAllocator = _pageFrameAllocator;

			try self.mapper.init(self.pageFrameAllocator);
			if (!global_initialized) {
				try global_init(self);
			}
			self.earlyUserAddressesAllocator = .{
				.address = 0, // todo
				.size = (paging.low_half / paging.page_size)
			};
			self.userAddressesAllocator = try VirtualAddressesAllocatorType.init(self, 0, (paging.low_half / paging.page_size));
			self.initialized = true;


		}

		pub fn global_init(_pageAllocator : anytype) (PageFrameAllocatorType.Error || VirtualAddressesAllocatorType.Error)!void {
			earlyKernelAddressesAllocator = .{
				.address = paging.low_half / paging.page_size,
				.size = paging.kernel_virtual_space_size / paging.page_size
			};
			kernelAddressesAllocator = try VirtualAddressesAllocatorType.init(_pageAllocator, paging.low_half / paging.page_size, paging.kernel_virtual_space_size / paging.page_size);
			// printk("truc {} {}\n", .{paging.low_half / paging.page_size, paging.kernel_virtual_space_size / paging.page_size});
			try kernelAddressesAllocator.set_used(ft.math.divCeil(usize, paging.low_half, paging.page_size) catch unreachable, ft.math.divCeil(usize, @import("../trampoline.zig").kernel_size, paging.page_size) catch unreachable);
			printk("truc  {} {}\n", .{ft.math.divCeil(usize, paging.low_half, paging.page_size) catch unreachable, ft.math.divCeil(usize, @import("../trampoline.zig").kernel_size, paging.page_size) catch unreachable});
			printk("troc  {}\n", .{kernelAddressesAllocator.node_pages.?.hdr.free_nodes_count});
			kernelAddressesAllocator.print();
			for (paging.page_dir_ptr[768..], 768..) |dir_entry, dir_index| {
				if (dir_entry.present) {
					const table = mapping.get_table_ptr(@truncate(dir_index));
					for (table[0..], 0..) |table_entry, table_index| {
						if (table_entry.present) {
							// printk("{} {}\n ", .{dir_index, table_index});
							kernelAddressesAllocator.set_used(@as(u32, @bitCast(paging.VirtualPtrStruct{.page_index = 0, .table_index = @truncate(table_index), .dir_index = @truncate(dir_index)})) >> 12, 1) catch {};
						}
					}
				}
			}
			printk("coucou\n", .{});
			global_initialized = true;
		}

		/// allocate virtual space
		fn alloc_virtual_space(self : *Self, npages : usize, allocType : AllocType) (PageFrameAllocatorType.Error || VirtualAddressesAllocatorType.Error)!paging.VirtualPagePtr {
			switch (allocType) {
				.UserSpace => {
					if (self.initialized) {
						return @ptrFromInt(try self.userAddressesAllocator.alloc_space(npages) * paging.page_size);
					} else {
						@setCold(true);
						return @ptrFromInt(try self.earlyUserAddressesAllocator.alloc_space(npages) * paging.page_size);
					}
				},
				.KernelSpace => {
					if (global_initialized) {
						return @ptrFromInt(try kernelAddressesAllocator.alloc_space(npages) * paging.page_size);
					} else {
						@setCold(true);
						return @ptrFromInt(try earlyKernelAddressesAllocator.alloc_space(npages) * paging.page_size);
					}
				}
			}
		}

		/// free virtual space
		fn free_virtual_space(self : *Self, address : paging.VirtualPagePtr, npages : usize) (VirtualAddressesAllocatorType.Error)!void {
			if (paging.is_user_space(address)) {
				if (self.initialized) {
					self.userAddressesAllocator.free_space(@intFromPtr(address) / paging.page_size, npages) catch @panic("double unmap1"); // todo
				} else {
					@setCold(true);
					self.earlyUserAddressesAllocator.free_space(@intFromPtr(address) / paging.page_size, npages) catch @panic("double unmap2"); // todo
				}
			} else {
				if (global_initialized) {
					kernelAddressesAllocator.free_space(@intFromPtr(address) / paging.page_size, npages) catch @panic("double unmap3"); // todo
				} else {
					@setCold(true);
					earlyKernelAddressesAllocator.free_space(@intFromPtr(address) / paging.page_size, npages) catch @panic("double unmap4"); // todo
				}
			}
		}

		/// allocate virtual space and map the area pointed by physical to this space
		pub fn map_anywhere(self : *Self, physical : paging.PhysicalPtr, len : usize, allocType : AllocType) (PageFrameAllocatorType.Error || VirtualAddressesAllocatorType.Error || Mapper.Error)!paging.VirtualPtr {
			const physical_pages = ft.mem.alignBackward(paging.PhysicalPtr, physical, paging.page_size);
			const npages = (ft.mem.alignForward(paging.PhysicalPtr, physical + len, paging.page_size) - physical_pages) / paging.page_size;
			const virtual = try self.alloc_virtual_space(npages, allocType); // todo

			errdefer self.free_virtual_space(virtual, npages) catch unreachable;

			try self.mapper.map(virtual, physical_pages, npages);
			return @ptrFromInt(@intFromPtr(virtual) + physical % paging.page_size);
		}

		/// map a virtual ptr to a physical ptr (all the page is mapped)
		pub fn map(self : *Self, physical : paging.PhysicalPtr, virtual: paging.VirtualPagePtr, npages : usize) !void {
			try self.mapper.map(virtual, physical, npages);
		}

		/// unmap a zone previously mapped
		// todo
		pub fn unmap(self : *Self, virtual: paging.VirtualPtr, n : usize) !void {
			const virtual_pages : paging.VirtualPagePtr = @ptrFromInt(ft.mem.alignBackward(usize, @as(usize, @intFromPtr(virtual)), paging.page_size)); // todo
			const npages = (ft.mem.alignForward(usize, @as(usize, @intFromPtr(virtual)) + n, paging.page_size) - @intFromPtr(virtual_pages)) / paging.page_size;
			try self.mapper.unmap(virtual_pages, npages);
			self.free_virtual_space(virtual_pages, npages) catch @panic("double unmap5");
		}

		/// unmap an area without freeing the virtual address space
		pub fn unmap_raw(self : *Self, virtual: paging.VirtualPtr, n : usize) void {
			const virtual_pages : paging.VirtualPagePtr = @ptrFromInt(ft.mem.alignBackward(usize, @as(usize, @intFromPtr(virtual)), paging.page_size)); // todo
			const npages = (ft.mem.alignForward(usize, @as(usize, @intFromPtr(virtual)) + n, paging.page_size) - @intFromPtr(virtual_pages)) / paging.page_size;
			self.mapper.unmap(virtual_pages, npages);
		}

		/// allocate npages pages with options
		pub fn alloc_pages_opt(self : *Self, npages : usize, options : AllocOptions) (PageFrameAllocatorType.Error || VirtualAddressesAllocatorType.Error)!paging.VirtualPagePtr
		{
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
					// errdefer self.pageFrameAllocator.free_pages(physical, 1) catch {};
					self.mapper.map(@ptrFromInt(@intFromPtr(virtual) + p * paging.page_size), physical, 1) catch unreachable;
				}
			}
			return @ptrCast(virtual);
		}

		/// allocate npages pages with default options
		pub fn alloc_pages(self : *Self, npages : usize) (PageFrameAllocatorType.Error || VirtualAddressesAllocatorType.Error)!paging.VirtualPagePtr { // todo: ret type
			return self.alloc_pages_opt(npages, .{});
		}

		/// free the `npages` pages at address `address` previously allocated using alloc_pages_opt or alloc_pages
		pub fn free_pages(self : *Self, address : paging.VirtualPagePtr, npages : usize) !void {
			for (0..npages) |p| {
				const virtual : paging.VirtualPagePtr = @ptrFromInt(@intFromPtr(address) + p * paging.page_size);
				// printk("A\n", .{});

				const physical = try mapping.get_physical_ptr(virtual);
				// printk("B\n", .{});

				try self.mapper.unmap(virtual, 1);
				// printk("C\n", .{});

				try self.pageFrameAllocator.free_pages(physical, 1);
				// printk("D\n", .{});

			}
			self.free_virtual_space(address, npages) catch return Error.DoubleFree;
		}

		/// return the page frame descriptor of the page pointed by `address`
		pub fn get_page_frame_descriptor(self : *Self, address : paging.VirtualPagePtr) !*paging.page_frame_descriptor {
			return self.pageFrameAllocator.get_page_frame_descriptor(try mapping.get_physical_ptr(address));
		}

		/// print debug infos
		pub fn print(self : *Self) void {
			printk("User space:\n", .{});
			self.userAddressesAllocator.print();
			printk("Kernel space:\n", .{});
			kernelAddressesAllocator.print();
		}
	};
}

