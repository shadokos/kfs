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
		pageFrameAllocator : *PageFrameAllocatorType = undefined,
		mapper : Mapper = .{},
		userAddressesAllocator : VirtualAddressesAllocatorType = .{},
		earlyUserAddressesAllocator : EarlyVirtualAddressesAllocator = undefined,
		initialized : bool = false,

		pub const AllocType = enum {
			KernelSpace,
			UserSpace
		};

		pub const AllocOptions = struct {
			type: AllocType = .UserSpace,
		};

		var kernelAddressesAllocator : VirtualAddressesAllocatorType = .{};
		// var earlyKernelAddressesAllocator : EarlyVirtualAddressesAllocator = .{};

		const Mapper = mapping.MapperT(PageFrameAllocatorType);

		pub const VirtualAddressesAllocatorType = VirtualAddressesAllocator(@This());

		pub const Error = VirtualAddressesAllocatorType.Error || PageFrameAllocatorType.Error;

		const Self = @This();

		pub fn init(self : *Self, _pageFrameAllocator : *PageFrameAllocatorType) Error!void {
			self.pageFrameAllocator = _pageFrameAllocator;

			try self.mapper.init(self.pageFrameAllocator);
			self.earlyUserAddressesAllocator = .{
				.address = 0, // todo
				.size = (paging.low_half / paging.page_size)
			};
			try self.userAddressesAllocator.init(self, 0, (paging.low_half / paging.page_size));
			self.initialized = true;
		}

		pub fn global_init(_pageAllocator : anytype) Error!void {
			kernelAddressesAllocator = .{};
			try kernelAddressesAllocator.init(_pageAllocator, paging.low_half / paging.page_size, paging.kernel_virtual_space_size / paging.page_size);
			try kernelAddressesAllocator.set_used(ft.math.divCeil(usize, paging.low_half, paging.page_size) catch unreachable, ft.math.divCeil(usize, @import("../trampoline.zig").kernel_size, paging.page_size) catch unreachable);
		}

		pub fn alloc_virtual_space(self : *Self, npages : usize, allocType : AllocType) (PageFrameAllocatorType.Error || VirtualAddressesAllocatorType.Error)!paging.VirtualPagePtr {
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
					return @ptrFromInt(try kernelAddressesAllocator.alloc_space(npages) * paging.page_size);
				}
			}
		}

		pub fn free_virtual_space(self : *Self, address : paging.VirtualPagePtr, npages : usize) (VirtualAddressesAllocatorType.Error)!void {
			if (paging.is_user_space(address)) {
				if (self.initialized) {
					self.userAddressesAllocator.free_space(@intFromPtr(address) / paging.page_size, npages) catch @panic("double unmap"); // todo
				} else {
					@setCold(true);
					self.earlyUserAddressesAllocator.free_space(@intFromPtr(address) / paging.page_size, npages) catch @panic("double unmap"); // todo
				}
			} else {
				kernelAddressesAllocator.free_space(@intFromPtr(address) / paging.page_size, npages) catch @panic("double unmap"); // todo
			}
		}

		pub fn map_anywhere(self : *Self, physical : paging.PhysicalPtr, len : usize, allocType : AllocType) (PageFrameAllocatorType.Error || VirtualAddressesAllocatorType.Error)!paging.VirtualPtr {
			const physical_pages = ft.mem.alignBackward(paging.PhysicalPtr, physical, paging.page_size);
			const npages = (ft.mem.alignForward(paging.PhysicalPtr, physical + len, paging.page_size) - physical_pages) / paging.page_size;
			// printk("coucou {d}\n", .{npages});
			const virtual = try self.alloc_virtual_space(npages, allocType); // todo

			try self.mapper.map(virtual, physical_pages, npages * paging.page_size);
			return @ptrFromInt(@intFromPtr(virtual) + physical % paging.page_size);
		}

		pub fn map(self : *Self, physical : paging.PhysicalPtr, virtual: paging.VirtualPtr, n : usize) void {
			try self.mapper.map(virtual, physical, n * paging.page_size);
		}

		pub fn unmap(self : *Self, virtual: paging.VirtualPtr, n : usize) void {
			const virtual_pages : paging.VirtualPagePtr = @ptrFromInt(ft.mem.alignBackward(usize, @as(usize, @intFromPtr(virtual)), paging.page_size)); // todo
			const npages = (ft.mem.alignForward(usize, @as(usize, @intFromPtr(virtual)) + n, paging.page_size) - @intFromPtr(virtual_pages)) / paging.page_size;
			// printk("npages: \x1b[31m{d}\x1b[0m ", .{npages});
			self.mapper.unmap(virtual_pages, npages);
			self.free_virtual_space(virtual_pages, npages) catch @panic("double unmap");
		}

		pub fn unmap_raw(self : *Self, virtual: paging.VirtualPtr, n : usize) void {
			const virtual_pages : paging.VirtualPagePtr = @ptrFromInt(ft.mem.alignBackward(usize, @as(usize, @intFromPtr(virtual)), paging.page_size)); // todo
			const npages = (ft.mem.alignForward(usize, @as(usize, @intFromPtr(virtual)) + n, paging.page_size) - @intFromPtr(virtual_pages)) / paging.page_size;
			self.mapper.unmap(virtual_pages, npages);
		}

		pub fn alloc_pages_opt(self : *Self, n : usize, options : AllocOptions) (PageFrameAllocatorType.Error || VirtualAddressesAllocatorType.Error)!paging.VirtualPagePtr
		{
			const virtual = try self.alloc_virtual_space(n, options.type);
			// printk("virtual {x}", .{@intFromPtr(virtual)});

			errdefer self.free_virtual_space(virtual, n) catch unreachable;

			const physical = try self.pageFrameAllocator.alloc_pages(n);
			errdefer self.pageFrameAllocator.free_pages(physical);

			// printk(", physical {x}\n", .{physical});
			try self.mapper.map(virtual, physical, n * paging.page_size);
			return @ptrCast(virtual);
		}

		pub fn alloc_pages(self : *Self, n : usize) (PageFrameAllocatorType.Error || VirtualAddressesAllocatorType.Error)!paging.VirtualPagePtr { // todo: ret type
			return self.alloc_pages_opt(n, .{});
		}

		pub fn free_pages(self : *Self, address : paging.VirtualPagePtr, n : usize) void {
			const physical = mapping.get_physical_ptr(address);
			self.pageFrameAllocator.free_pages(physical);
			// self.unmap(@ptrCast(address), n);
			self.mapper.unmap(@ptrCast(@alignCast(address)), n);
			self.free_virtual_space(address, n) catch @panic("double free"); // todo
		}

		pub fn get_page_frame_descriptor(self : *Self, address : paging.VirtualPagePtr) *paging.page_frame_descriptor {
			return self.pageFrameAllocator.get_page_frame_descriptor(mapping.get_physical_ptr(address));
		}

		pub fn print(self : *Self) void {
			printk("User space:\n", .{});
			self.userAddressesAllocator.print();
			printk("Kernel space:\n", .{});
			kernelAddressesAllocator.print();
		}
	};
}

