const paging = @import("paging.zig");
const ft = @import("../ft/ft.zig");
const printk = @import("../tty/tty.zig").printk;
const VirtualAddressesAllocator = @import("virtual_addresses_allocator.zig").VirtualAddressesAllocator;
const PageFrameAllocator = @import("page_frame_allocator.zig").PageFrameAllocator;
const mapping = @import("mapping.zig").mapping;
const memory = @import("../memory.zig").mapping;

pub fn VirtualPageAllocator(comptime PageFrameAllocatorType : type) type {
	return struct {
		pageFrameAllocator : *PageFrameAllocatorType = undefined,
		mapper : Mapper = .{},
		userAddressesAllocator : VirtualAddressesAllocatorType = .{},
		initialized : bool = false,

		pub const AllocOptions = enum {
			KernelSpace,
			UserSpace
		};

		var kernelAddressesAllocator : VirtualAddressesAllocatorType = .{};

		const Mapper = mapping(PageFrameAllocatorType);

		pub const VirtualAddressesAllocatorType = VirtualAddressesAllocator(@This());

		pub const Error = VirtualAddressesAllocatorType.Error || PageFrameAllocatorType.Error;

		const Self = @This();

		pub fn init(self : *Self, _pageFrameAllocator : *PageFrameAllocatorType) Error!void {
			self.pageFrameAllocator = _pageFrameAllocator;
			try self.mapper.init(self.pageFrameAllocator);
			try self.userAddressesAllocator.init(self, 0, paging.low_half / paging.page_size);
			self.initialized = true;
		}

		pub fn global_init(_pageAllocator : anytype) Error!void {
			kernelAddressesAllocator = .{};
			try kernelAddressesAllocator.init(_pageAllocator, paging.low_half / paging.page_size, paging.kernel_virtual_space_size / paging.page_size);
		}

		pub fn alloc_virtual_space(self : *Self, npages : usize) (PageFrameAllocatorType.Error || VirtualAddressesAllocatorType.Error)!paging.VirtualPagePtr {
			if (self.initialized) {
				return @ptrFromInt(try self.userAddressesAllocator.alloc_space(npages) * paging.page_size);
			} else {
				@setCold(true);
				for (paging.page_dir_ptr[0..], 0..) |dir_entry, dir_index| {
					if (dir_entry.present) {
						const table = Mapper.get_table_ptr(@intCast(dir_index));
						for (table.*, 0..) |table_entry, table_index| {
							if (!Mapper.is_page_mapped(table_entry)) {
								return @ptrFromInt(@as(u32, @bitCast(
								paging.VirtualPtrStruct{
								.dir_index = @intCast(dir_index),
								.table_index = @intCast(table_index),
								.page_index = 0,
								}
								)));
							}
						}
					} else {
						return @ptrFromInt(@as(u32, @bitCast(
							paging.VirtualPtrStruct{
								.dir_index = @intCast(dir_index),
								.table_index = 0,
								.page_index = 0,
							}
						)));
					}
				}
				return Error.NoSpaceFound;
			}
		}

		pub fn map_anywhere(self : *Self, physical : paging.PhysicalPtr, len : usize) (PageFrameAllocatorType.Error || VirtualAddressesAllocatorType.Error)!paging.VirtualPtr {

			const physical_pages = ft.mem.alignBackward(paging.PhysicalPtr, physical, paging.page_size);

			const npages = ft.math.divCeil(usize, len, paging.page_size) catch @panic("map_anywhere");
			const virtual = try self.alloc_virtual_space(npages);

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
			const physical = try self.pageFrameAllocator.alloc_pages(n);
			// const virtual = switch (options) {
			// 	.KernelSpace => try kernelAddressesAllocator.alloc_virtual_space(n),
			// 	.UserSpace => try self.alloc_virtual_space(n),
			// };
			_ = options;
			const virtual = try self.alloc_virtual_space(n);
			try self.mapper.map(virtual, physical, n * paging.page_size);
			return @ptrCast(virtual);
		}

		pub fn alloc_pages(self : *Self, n : usize) (PageFrameAllocatorType.Error || VirtualAddressesAllocatorType.Error)!paging.VirtualPagePtr { // todo: ret type
			return self.alloc_pages_opt(n, .UserSpace);
		}

		pub fn free_pages(self : *Self, address : paging.VirtualPagePtr, n : usize) void {
			const physical = Mapper.get_physical_ptr(address);
			self.pageFrameAllocator.free_pages(physical);
			self.unmap(@ptrCast(address), n);
		}

	};
}

