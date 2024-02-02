const boot = @import("boot.zig");
const ft = @import("ft/ft.zig");
const tty = @import("./tty/tty.zig");
const printk = @import("./tty/tty.zig").printk;
const BuddyAllocator = @import("memory/buddy_allocator.zig").BuddyAllocator;
const paging = @import("memory/paging.zig");
const multiboot = @import("multiboot.zig");
const multiboot2_h = @import("c_headers.zig").multiboot2_h;

pub var page_allocator : BuddyAllocator(@TypeOf(boot.linearAllocator), 10) = .{};

extern const kernel_end : u32;

var total_space : u64 = undefined;

pub fn init() void {
	total_space = get_max_mem();

	page_allocator.set_allocator(&boot.linearAllocator);

	if (total_space > page_allocator.max_possible_space(u64))
		@panic("thats a lot of ram!");

	page_allocator.init(@intCast(total_space / @sizeOf(paging.page)));

	boot.linearAllocator.lock();

	check_mem_availability();
}

fn check_mem_availability() void {
	const page_size = @sizeOf(paging.page);

	if (multiboot.get_tag(multiboot2_h.MULTIBOOT_TAG_TYPE_MMAP)) |t| {
		var iter = multiboot.mmap_it{.base = t};
		while (iter.next()) |e| {
			if (e.type != multiboot2_h.MULTIBOOT_MEMORY_AVAILABLE)
				continue;
			var area_begin : u64 = @intCast(ft.mem.alignForward(@TypeOf(e.base), e.base, page_size));
			const area_end : u64 = @intCast(ft.mem.alignBackward(@TypeOf(e.base), e.base + e.length, page_size));
			if (area_begin >= area_end) // smaller than a page
				continue;
			while (area_begin < area_end) : (area_begin += page_size) {
				if (area_begin < @intFromPtr(&kernel_end)) // area is before kernel end
					continue;
				if ((area_begin > boot.linearAllocator.lower_bound() and area_begin < boot.linearAllocator.upper_bound()) or
					((area_begin + page_size) > boot.linearAllocator.lower_bound() and (area_begin + page_size) < boot.linearAllocator.upper_bound())) // area overlap space allocated by the linear_allocator
					continue;
				page_allocator.frame_from_idx(@intCast(area_begin / @sizeOf(paging.page))).flags.available = true;
				page_allocator.free_page(@intCast(area_begin / page_size));
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
