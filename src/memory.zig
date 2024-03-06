const boot = @import("boot.zig");
const ft = @import("ft/ft.zig");
const tty = @import("./tty/tty.zig");
const printk = @import("./tty/tty.zig").printk;
const PageFrameAllocator = @import("memory/page_frame_allocator.zig").PageFrameAllocator;
const paging = @import("memory/paging.zig");
const multiboot = @import("multiboot.zig");
const multiboot2_h = @import("c_headers.zig").multiboot2_h;
const mapping = @import("memory/mapping.zig");
const VirtualPageAllocator = @import("memory/virtual_page_allocator.zig").VirtualPageAllocator;
const KernelMemoryAllocator = @import("memory/kernel_memory_allocator.zig").KernelMemoryAllocator;

pub const VirtualPageAllocatorType = VirtualPageAllocator(PageFrameAllocator);

pub var virtualPageAllocator : VirtualPageAllocatorType = .{};

pub var pageFrameAllocator : PageFrameAllocator = .{};

pub var global_cache: @import("memory/cache.zig").GlobalCache = undefined;

pub var kernelMemoryAllocator : KernelMemoryAllocator = .{};

var total_space : u64 = undefined;

pub fn map_kernel() void {

	// create space for all the tables of the kernel space
	const tables : * align(4096) [256][paging.page_table_size]paging.page_table_entry = @ptrCast((virtualPageAllocator.alloc_pages_opt(256, .{.type = .KernelSpace}) catch @panic("todo")));
	// at the end of this functions the page tables are only unmapped but not freed
	defer virtualPageAllocator.unmap(@ptrCast(tables), 256 * paging.page_size);

	// init all the page tables of the kernelspace
	for (0..(paging.kernel_virtual_space_size >> 22)) |i| {
		if (paging.page_table_table_ptr[768 + i].present) {
			@memcpy(tables[i][0..], mapping.get_table_ptr(@intCast(768 + i))[0..]);
			paging.page_dir_ptr[768 + i].address_fragment = @intCast(mapping.get_physical_ptr(@ptrCast(&tables[i])) >> 12);
		} else {
			@memset(tables[i][0..], paging.page_table_entry{});
			paging.page_dir_ptr[768 + i].address_fragment = @intCast(mapping.get_physical_ptr(@ptrCast(&tables[i])) >> 12);
			paging.page_table_table_ptr[768 + i].present = true;
		}
	}

	// set kernelspace to supervisor only mapping
	for (0..256) |i| {
		paging.page_table_table_ptr[768 + i].owner = .Supervisor;
	}

	// set read only kernel sections to non writable mapping for extra safety
	if (multiboot.get_tag(multiboot2_h.MULTIBOOT_TAG_TYPE_ELF_SECTIONS)) |t| {
		var iter = multiboot.section_hdr_it{.base = t};
		while (iter.next()) |e| {
			if (e.sh_addr >= paging.low_half) {
				if (!e.sh_flags.SHF_WRITE) {
					virtualPageAllocator.mapper.set_rights(@ptrFromInt(e.sh_addr), ft.math.divCeil(u32, e.sh_size, paging.page_size) catch unreachable, false);
				}
			}
		}
	}

	// free the spaces taken by the early page tables
	for (&@import("trampoline.zig").page_tables) |*table| {
		pageFrameAllocator.free_pages(@intFromPtr(table), 1) catch @panic("todo");
		const mapped = virtualPageAllocator.map_anywhere(@intFromPtr(table), paging.page_size, .KernelSpace) catch @panic("todo");
		@memset(@as(paging.VirtualPagePtr, @ptrCast(@alignCast(mapped))), 0);
		virtualPageAllocator.unmap(mapped, paging.page_size);
	}

	// shrink the kernel executable space to its actual size
	const kernel_aligned_begin = ft.mem.alignForward(usize, @intFromPtr(boot.kernel_end) + paging.low_half, paging.page_size);
	const kernel_aligned_end = ft.mem.alignForward(usize, @import("trampoline.zig").kernel_size + paging.low_half, paging.page_size);
	virtualPageAllocator.unmap(@ptrFromInt(kernel_aligned_begin), kernel_aligned_end - kernel_aligned_begin);
}

pub fn init() void {
	total_space = get_max_mem();

	printk("total space: {x}\n", .{total_space});

	pageFrameAllocator.init(total_space);

	check_mem_availability();

	virtualPageAllocator.init(&pageFrameAllocator) catch @panic("cannot init virtualPageAllocator");

	VirtualPageAllocatorType.global_init(&virtualPageAllocator) catch @panic("cannot global_init virtualPageAllocator");

	map_kernel();

	const GlobalCache = @import("memory/cache.zig").GlobalCache;
	global_cache = GlobalCache.init(&virtualPageAllocator) catch @panic("cannot init global_cache");
	KernelMemoryAllocator.cache_init() catch @panic("cannot cache_init KernelMemoryAllocator");
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
				pageFrameAllocator.free_pages(area_begin, 1) catch @panic("todo"); // todo
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
