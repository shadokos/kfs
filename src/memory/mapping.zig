const paging = @import("paging.zig");
const ft = @import("../ft/ft.zig");
const printk = @import("../tty/tty.zig").printk;
const VirtualAddressesAllocator = @import("virtual_addresses_allocator.zig").VirtualAddressesAllocator;

pub fn get_physical_ptr(virtual : paging.VirtualPagePtr) paging.PhysicalPtr { // todo error
	const virtualStruct : paging.VirtualPtrStruct = @bitCast(@as(u32, @intFromPtr(virtual)));
	const table : *[paging.page_table_size]paging.page_table_entry = get_table_ptr(virtualStruct.dir_index);
	const page : paging.PhysicalPtr = @as(paging.PhysicalPtr, table[virtualStruct.table_index].address_fragment) << 12;
	return page + virtualStruct.page_index;
}

pub fn is_page_mapped(table_entry : paging.page_table_entry) bool {
	return @as(u32, @bitCast(table_entry)) != 0;
}

pub fn get_table_ptr(table : paging.dir_idx) *[paging.page_table_size]paging.page_table_entry {
	return @ptrFromInt(@as(u32, @bitCast(paging.VirtualPtrStruct{
	.dir_index = paging.page_dir >> 22,
	.table_index = table,
	.page_index = 0,
	})));
}

pub fn MapperT(comptime PageFrameAllocatorType : type) type {
	return struct {
		pageFrameAllocator : *PageFrameAllocatorType = undefined,

		page_directory : [paging.page_directory_size]paging.page_directory_entry align(paging.page_size) = undefined,


		pub const Error = error{};

		const Self = @This();

		pub fn init(self : *Self, _pageFrameAllocator : *PageFrameAllocatorType) PageFrameAllocatorType.Error!void {
			self.pageFrameAllocator = _pageFrameAllocator;

			try self.transfer();

		}

		fn init_table(self : *Self, table : paging.dir_idx) PageFrameAllocatorType.Error!void {

			const table_physical_ptr : paging.PhysicalPtr = try self.pageFrameAllocator.alloc_pages(1);

			self.page_directory[table] = .{
				.address_fragment = @intCast(table_physical_ptr >> paging.page_bits), // todo: secure the cast
				.present = true,
				.owner = .User,
				.writable = true,
			};

			const table_virtual_ptr : *[paging.page_table_size]paging.page_table_entry = @ptrFromInt(@as(u32, @bitCast(
				paging.VirtualPtrStruct{
					.dir_index = paging.page_dir >> 22,
					.table_index = table,
					.page_index = 0,
				}
			)));

			@memset(table_virtual_ptr[0..], paging.page_table_entry{});
		}

		fn map_one(self : *Self, virtual: paging.VirtualPagePtr, physical : paging.PhysicalPtr) PageFrameAllocatorType.Error!void {
			const virtualStruct : paging.VirtualPtrStruct = @bitCast(@intFromPtr(virtual));

			if (!self.page_directory[virtualStruct.dir_index].present)
				try self.init_table(virtualStruct.dir_index);

			const table = get_table_ptr(virtualStruct.dir_index);

			const entry : paging.page_table_entry = .{
				.address_fragment = @intCast(physical >> paging.page_bits), // todo: secure the cast
				.present = true,
				.owner = .User,
				.writable = true,
			};

			if (is_page_mapped(table[virtualStruct.table_index])) {
				if (@as(u32, @bitCast(table[virtualStruct.table_index])) == @as(u32, @bitCast(entry)))
					return ;
				@panic("page already mapped");
				// todo return some error
			}
			table[virtualStruct.table_index] = entry;
		}

		pub fn unmap(self : *Self, virtual: paging.VirtualPagePtr, len : usize) void {
			for (0..len) |i| {
				const virtualStruct : paging.VirtualPtrStruct = @bitCast(@intFromPtr(virtual) + i * paging.page_size);
				if (!self.page_directory[virtualStruct.dir_index].present) {
				@panic("invalid unmap");
				// return; // todo
				}
				const table = get_table_ptr(virtualStruct.dir_index);
				table[virtualStruct.table_index] = @bitCast(@as(u32, 0));
			}
		}

		pub fn map(self : *Self, virtual: paging.VirtualPagePtr, physical : paging.PhysicalPtr, len : usize) PageFrameAllocatorType.Error!void {
			if (@intFromPtr(virtual) % paging.page_size != physical % paging.page_size)
				@panic("misaligned addresses"); // todo

			const virtual_pages : usize = (ft.mem.alignBackward(usize, @intFromPtr(virtual), paging.page_size));
			const physical_pages = ft.mem.alignBackward(paging.PhysicalPtr, physical, paging.page_size);

			// printk("map (v->p) : 0x{x:0>8} -> 0x{x:0>8}\n", .{virtual_pages, physical_pages});

			for (0..ft.math.divCeil(usize, len, paging.page_size) catch unreachable) |p| {
				try self.map_one(@ptrFromInt(virtual_pages + p * paging.page_size), physical_pages + p * paging.page_size);
			}
		}

		pub fn activate(self : *Self) void {
			asm volatile (
             \\ mov %eax, %cr3
             :
             : [_] "{eax}" (get_physical_ptr(@ptrCast(&self.page_directory))),
			);
		}

		fn transfer(self : *Self) PageFrameAllocatorType.Error!void {
    		@memcpy(self.page_directory[0..], paging.page_dir_ptr);
    		self.page_directory[paging.page_dir >> 22] = .{
				.present = true,
				.writable = true,
    			.address_fragment = @intCast(get_physical_ptr(@ptrCast(&self.page_directory)) >> 12)
    		};
    		self.activate();
			const virtual_tmp : @TypeOf(paging.page_table_table_ptr) = @ptrFromInt(paging.temporary_page);
    		for (paging.page_table_table_ptr[0..(paging.low_half >> 22)], 0..) |*e, i| {
    			if (e.present and i != (paging.page_dir >> 20)) {
    				const physical = try self.pageFrameAllocator.alloc_pages(1);
    				try self.map_one(@ptrCast(virtual_tmp), physical);
    				@memcpy(virtual_tmp[0..], get_table_ptr(@intCast(i)));
    				self.unmap(@ptrCast(virtual_tmp), 1);
    				e.address_fragment = @intCast(physical >> 12);
    			}
    		}
		}
	};
}