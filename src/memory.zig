const boot = @import("boot.zig");
const ft = @import("ft/ft.zig");
const tty = @import("./tty/tty.zig");
const printk = @import("./tty/tty.zig").printk;
// const BuddyAllocator = @import("memory/buddy_allocator.zig").BuddyAllocator;
const PageFrameAllocator = @import("memory/page_frame_allocator.zig").PageFrameAllocator;
const paging = @import("memory/paging.zig");
const multiboot = @import("multiboot.zig");
const multiboot2_h = @import("c_headers.zig").multiboot2_h;
const mapping = @import("memory/mapping.zig").mapping;
const VirtualPageAllocator = @import("memory/virtual_page_allocator.zig").VirtualPageAllocator;

pub const VirtualPageAllocatorType = VirtualPageAllocator(PageFrameAllocator);

pub var virtualPageAllocator : VirtualPageAllocatorType = .{};

// const VirtualAddressesAllocator = @import("virtual_addresses_allocator.zig").VirtualAddressesAllocator;
//
// const VirtualAddressesAllocatorType = VirtualAddressesAllocator(VirtualPageAllocatorType);
//
// pub var kernel_addresses_allocator : VirtualAddressesAllocatorType = .{};


pub var pageFrameAllocator : PageFrameAllocator = .{};

var total_space : u64 = undefined;

// pub const Mapper = mapping(@TypeOf(pageFrameAllocator));
//
// pub var mapper : Mapper = .{};

extern var stack_bottom : [*]u8;

pub fn map_kernel() void {
	const page_dir_physical = pageFrameAllocator.alloc_pages(1) catch @panic("cannot allocate");
		paging.page_dir_ptr[511] = .{
			.address_fragment = @intCast(page_dir_physical >> paging.page_bits), // todo: secure the cast
			.present = true,
			.writable = true,
		};


	const page_dir_ptr : *[paging.page_table_size]paging.page_table_entry = @ptrFromInt(@as(u32, @bitCast(
		paging.VirtualPtrStruct{
		.dir_index = paging.page_dir >> 22,
		.table_index = 511,
		.page_index = 0,
		}
	)));

	@memset(page_dir_ptr, paging.page_table_entry{});

	// const physical = pageFrameAllocator.alloc_pages(256) catch @panic("cannot allocate");
	for (0..256) |table| {
		printk("table: {d}\n", .{table});
		// const current_physical = physical + paging.page_size * table;
		const current_physical = pageFrameAllocator.alloc_pages(1) catch @panic("cannot allocate");
		paging.page_dir_ptr[512] = .{
			.address_fragment = @intCast(current_physical >> paging.page_bits), // todo: secure the cast
			.present = true,
			.writable = true,
		};

		const table_virtual_ptr : *[paging.page_table_size]paging.page_table_entry = @ptrFromInt(@as(u32, @bitCast(
			paging.VirtualPtrStruct{
			.dir_index = paging.page_dir >> 22,
			.table_index = 512,
			.page_index = 0,
			}
		)));

		for (0..1024) |p| {
			// table_virtual_ptr[p] = before[p];
			table_virtual_ptr[p] = .{
				.address_fragment = @intCast((table << 10) + p), // todo: secure the cast
				.present = true,
				.writable = true,
			};
		}

		page_dir_ptr[768 + table] = .{
			.address_fragment = @intCast(current_physical >> paging.page_bits), // todo: secure the cast
			.present = true,
			.writable = true,
		};
		page_dir_ptr[table] = page_dir_ptr[768 + table];
	}

	page_dir_ptr[1023] = .{
		.address_fragment = @intCast(page_dir_physical >> paging.page_bits), // todo: secure the cast
		.present = true,
		.writable = true,
	};

	asm volatile (
	\\ mov %eax, %cr3
	:
	: [_] "{eax}" (page_dir_physical),
	);
	while (true) {}
}

pub fn init() void {
	total_space = get_max_mem();

	printk("total space: {x}\n", .{total_space});

	pageFrameAllocator.init(total_space);

	check_mem_availability();

	// map_kernel();
	//
	virtualPageAllocator.init(&pageFrameAllocator) catch @panic("cannot init virtualPageAllocator");
	VirtualPageAllocatorType.global_init(&virtualPageAllocator) catch @panic("cannot global_init virtualPageAllocator");
	// virtualPageAllocator.map_kernel();

// mapper.init(&pageFrameAllocator) catch @panic("cannot init mapper");

}
fn check_mem_availability() void {
	const page_size = @sizeOf(paging.page);

	if (multiboot.get_tag(multiboot2_h.MULTIBOOT_TAG_TYPE_MMAP)) |t| {
		var iter = multiboot.mmap_it{.base = t};
		while (iter.next()) |e| {
			if (e.type != multiboot2_h.MULTIBOOT_MEMORY_AVAILABLE)
				continue;
			var area_begin : paging.PhysicalPtr = @intCast(ft.mem.alignForward(@TypeOf(e.base), e.base, page_size)); // todo: secure cast
			const area_end : paging.PhysicalPtr = @intCast(ft.mem.alignBackward(@TypeOf(e.base), e.base + e.length, page_size)); // todo: secure cast
			if (area_begin >= area_end) // smaller than a page
				continue;
			while (area_begin < area_end) : (area_begin += page_size) {
				if (area_begin < @intFromPtr(boot.kernel_end)) // area is before kernel end
					continue;
				// if ((area_begin > boot.linearAllocator.lower_bound() and area_begin < boot.linearAllocator.upper_bound()) or
				// 	((area_begin + page_size) > boot.linearAllocator.lower_bound() and (area_begin + page_size) < boot.linearAllocator.upper_bound())) // area overlap space allocated by the linear_allocator
				// 	continue;
				pageFrameAllocator.free_pages(area_begin);
			}
		}
	}
}

fn get_max_mem() u64 {
	var max : u64 = 0;
	if (multiboot.get_tag(multiboot2_h.MULTIBOOT_TAG_TYPE_MMAP)) |t| {
		var iter = multiboot.mmap_it{.base = t};
		while (iter.next()) |e| {
			if (e.base + e.length > max)
				max = @intCast(e.base + e.length);
		}
	} else @panic("no mmap");
	return max;
}
