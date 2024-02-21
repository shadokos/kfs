const LinearAllocator = @import("linear_allocator.zig").LinearAllocator;
const StaticAllocator = @import("static_allocator.zig").StaticAllocator;
const BuddyAllocator = @import("buddy_allocator.zig").BuddyAllocator;
const paging = @import("paging.zig");

pub var linearAllocator : StaticAllocator(BuddyAllocator(void, 10).size_for(paging.virtual_size / paging.page_size)) = .{};

pub const PageFrameAllocator = struct {
	total_space : u64 = undefined,
	addressable_space_allocator : UnderlyingAllocator = .{},
	non_addressable_space_allocator : UnderlyingAllocator = .{},

	pub const UnderlyingAllocator = BuddyAllocator(@TypeOf(linearAllocator), 10);

	pub const Error = UnderlyingAllocator.Error;

	const Self = @This();

	pub fn init(self : *Self, _total_space : u64) void {
		self.total_space = _total_space;
		self.total_space = @min(self.total_space, paging.physical_memory_max);

		self.addressable_space_allocator.set_allocator(&linearAllocator);
		// @import("../tty/tty.zig").printk("truc: {d}\n", .{self.total_space});
		// @import("../tty/tty.zig").printk("truc: {d}\n", .{self.addressable_space_allocator.max_possible_space(u64)});
		// @import("../tty/tty.zig").printk("truc: {x}\n", .{UnderlyingAllocator.size_for(self.addressable_space_allocator.max_possible_space(usize))});
		if (self.total_space > self.addressable_space_allocator.max_possible_space(u64))
			@panic("thats a lot of ram!"); // todo
		self.addressable_space_allocator.init(@intCast(@min(self.total_space, paging.physical_memory_max) / @sizeOf(paging.page)));

		if (self.total_space > paging.physical_memory_max)
		{
			const high_memory_space = self.total_space - paging.physical_memory_max;
			self.non_addressable_space_allocator.set_allocator(&linearAllocator);
			self.non_addressable_space_allocator.init(@intCast(high_memory_space / @sizeOf(paging.page)));
		}
	}

	pub fn alloc_pages(self : *Self, n : usize) Error!paging.PhysicalPtr {
		return if (self.non_addressable_space_allocator.alloc_pages(n)) |v|
				v * @sizeOf(paging.page) + paging.physical_memory_max
		else |_| if (self.addressable_space_allocator.alloc_pages(n)) |v|
				v * @sizeOf(paging.page)
		else |err| err;
	}

	pub fn alloc_pages_hint(self : *Self, hint : paging.PhysicalPtr, n : usize) Error!paging.PhysicalPtr {
		return if (self.non_addressable_space_allocator.alloc_pages_hint(hint / @sizeOf(paging.page), n)) |v|
				v * @sizeOf(paging.page) + paging.physical_memory_max
		else |_| if (self.addressable_space_allocator.alloc_pages_hint(hint / @sizeOf(paging.page), n)) |v|
				v * @sizeOf(paging.page)
		else |err| err;
	}

	pub fn free_pages(self : *Self, ptr : paging.PhysicalPtr) void {
		if (ptr < paging.physical_memory_max)
			self.addressable_space_allocator.free_pages(@intCast(ptr / @sizeOf(paging.page))) // todo: div can overflow
		else
			self.non_addressable_space_allocator.free_pages(@intCast(ptr / @sizeOf(paging.page)));
	}

	pub fn get_page_frame_descriptor(self : *Self, ptr : paging.PhysicalPtr) *paging.page_frame_descriptor {
		return if (ptr < paging.physical_memory_max)
			self.addressable_space_allocator.frame_from_idx(@intCast(ptr / @sizeOf(paging.page))) // todo: div can overflow
		else
			self.non_addressable_space_allocator.frame_from_idx(@intCast(ptr / @sizeOf(paging.page)));
	}
};
