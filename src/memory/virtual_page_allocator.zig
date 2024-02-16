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
				.address = 0,
				.size = paging.low_half / paging.page_size
			};
			try self.userAddressesAllocator.init(self, 0, paging.low_half / paging.page_size);
			self.initialized = true;
		}

		pub fn global_init(_pageAllocator : anytype) Error!void {
			kernelAddressesAllocator = .{};
			// try earlyKernelAddressesAllocator.init(_pageAllocator, paging.low_half / paging.page_size, paging.kernel_virtual_space_size / paging.page_size);
			try kernelAddressesAllocator.init(_pageAllocator, paging.low_half / paging.page_size, paging.kernel_virtual_space_size / paging.page_size);
			try kernelAddressesAllocator.set_used(ft.math.divCeil(usize, paging.low_half, paging.page_size) catch unreachable, ft.math.divCeil(usize, @intFromPtr(@import("../boot.zig").kernel_end), paging.page_size) catch unreachable);
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

		pub fn map_anywhere(self : *Self, physical : paging.PhysicalPtr, len : usize) (PageFrameAllocatorType.Error || VirtualAddressesAllocatorType.Error)!paging.VirtualPtr {

			const physical_pages = ft.mem.alignBackward(paging.PhysicalPtr, physical, paging.page_size);
			const npages = ft.math.divCeil(usize, len, paging.page_size) catch @panic("map_anywhere");
			const virtual = try self.alloc_virtual_space(npages, .KernelSpace); // todo

			try self.mapper.map(virtual, physical_pages, npages * paging.page_size);
			return @ptrCast(virtual);
		}

		pub fn map(self : *Self, physical : paging.PhysicalPtr, virtual: paging.VirtualPtr, n : usize) void {
			try self.mapper.map(virtual, physical, n * paging.page_size);
		}

		pub fn unmap(self : *Self, virtual: paging.VirtualPtr, n : usize) void {
			self.mapper.unmap(@ptrCast(@alignCast(virtual)), n);
			self.userAddressesAllocator.free_space(@intFromPtr(virtual) / paging.page_size, n) catch @panic("double unmap"); // todo
		}

		pub fn alloc_pages_opt(self : *Self, n : usize, options : AllocOptions) (PageFrameAllocatorType.Error || VirtualAddressesAllocatorType.Error)!paging.VirtualPagePtr
		{
			// const virtual = switch (options) {
			// 	.KernelSpace => try kernelAddressesAllocator.alloc_virtual_space(n),
			// 	.UserSpace => try self.alloc_virtual_space(n),
			// };
			const virtual = try self.alloc_virtual_space(n, options.type);
			const physical = self.pageFrameAllocator.alloc_pages(n) catch |err| {
				try self.free_virtual_space(virtual, n);
				return err;
			};
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
	};
}

