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
const VirtualMemory = @import("memory/virtual_memory.zig").VirtualMemory;
const PhysicalMemory = @import("memory/physical_memory.zig").PhysicalMemory;
const logger = @import("ft/ft.zig").log.scoped(.memory);


pub const VirtualPageAllocatorType = VirtualPageAllocator(PageFrameAllocator);
pub var virtualPageAllocator : VirtualPageAllocatorType = .{};

pub var pageFrameAllocator : PageFrameAllocator = .{};

pub const VirtualMemoryType = VirtualMemory(VirtualPageAllocatorType);
pub var virtualMemory : VirtualMemoryType = undefined;

pub var globalCache: @import("memory/cache.zig").GlobalCache = undefined;

pub var physicalMemory : PhysicalMemory = .{};

pub fn map_kernel() void {

	// create space for all the tables of the kernel space
	const tables : * align(4096) [256][paging.page_table_size]paging.page_table_entry = @ptrCast((virtualPageAllocator.alloc_pages_opt(256, .{.type = .KernelSpace}) catch @panic("not enought space to map kernel")));
	// at the end of this functions the page tables are only unmapped but not freed
	defer virtualPageAllocator.unmap_object(@ptrCast(tables), 256 * paging.page_size) catch unreachable;

	// init all the page tables of the kernelspace
	for (0..(paging.kernel_virtual_space_size >> 22)) |i| {
		if (paging.page_table_table_ptr[768 + i].present) {
			@memcpy(tables[i][0..], mapping.get_table_ptr(@intCast(768 + i))[0..]);
			paging.page_dir_ptr[768 + i].address_fragment = @truncate((mapping.get_physical_ptr(@ptrCast(&tables[i])) catch unreachable) >> 12);
		} else {
			@memset(tables[i][0..], paging.page_table_entry{});
			paging.page_dir_ptr[768 + i].address_fragment = @truncate((mapping.get_physical_ptr(@ptrCast(&tables[i])) catch unreachable) >> 12);
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
					virtualPageAllocator.mapper.set_rights(@ptrFromInt(e.sh_addr), ft.math.divCeil(u32, e.sh_size, paging.page_size) catch unreachable, false) catch unreachable;
				}
			}
		}
	}

	// free the spaces taken by the early page tables
	for (&@import("trampoline.zig").page_tables) |*table| {
		pageFrameAllocator.free_pages(@intFromPtr(table), 1) catch unreachable;
		const mapped = virtualPageAllocator.map_object_anywhere(@intFromPtr(table), paging.page_size, .KernelSpace) catch @panic("cannot init memory");
		@memset(@as(paging.VirtualPagePtr, @ptrCast(@alignCast(mapped))), 0);
		virtualPageAllocator.unmap_object(mapped, paging.page_size) catch unreachable;
	}

	// shrink the kernel executable space to its actual size
	const kernel_aligned_begin = ft.mem.alignForward(usize, @intFromPtr(boot.kernel_end) + paging.low_half, paging.page_size);
	const kernel_aligned_end = ft.mem.alignForward(usize, @import("trampoline.zig").kernel_size + paging.low_half, paging.page_size);
	virtualPageAllocator.unmap_object(@ptrFromInt(kernel_aligned_begin), kernel_aligned_end - kernel_aligned_begin) catch @panic("can't shrink kernel");
}

pub fn init() void {

	logger.debug("Initializing memory", .{});

	var total_space : u64 = get_max_mem();

	logger.debug("\ttotal_space: {x}", .{total_space});

	logger.debug("\tInitializing page frame allocator...", .{});
	pageFrameAllocator = PageFrameAllocator.init(total_space);
	logger.debug("\tPage frame allocator initialized", .{});

	logger.debug("\tCheck ram availability", .{});
	check_mem_availability();

	logger.debug("\tInitializing virtual page allocator...", .{});
	virtualPageAllocator.init(&pageFrameAllocator) catch |e| {
		logger.err("error: {s}", .{@errorName(e)});
		@panic("cannot init virtualPageAllocator");
	};
	logger.debug("\tVirtual page allocator initialized", .{});

	logger.debug("\tRemapping kernel...", .{});
	map_kernel();
	logger.debug("\tKernel remapped", .{});

	logger.debug("\tInitializing slab allocator's global cache...", .{});
	const GlobalCache = @import("memory/cache.zig").GlobalCache;
	globalCache = GlobalCache.init(&virtualPageAllocator) catch @panic("cannot init globalCache");
	logger.debug("\tGlobal cache initialized", .{});

	logger.debug("\tInitializing physical memory allocator...", .{});
	PhysicalMemory.cache_init() catch @panic("cannot cache_init PhysicalMemory");
	logger.debug("\tPhysical memory allocator initialized", .{});

	logger.debug("\tInitializing virtual memory allocator...", .{});
	virtualMemory = VirtualMemoryType.init(&virtualPageAllocator);
	logger.debug("\tVirtual memory allocator initialized", .{});

	logger.info("Memory initialized", .{});
}

fn check_mem_availability() void {
	const page_size = @sizeOf(paging.page);
	if (multiboot.get_tag(multiboot2_h.MULTIBOOT_TAG_TYPE_MMAP)) |t| {
		var iter = multiboot.mmap_it{.base = t};
		while (iter.next()) |e| {
			if (e.type != multiboot2_h.MULTIBOOT_MEMORY_AVAILABLE)
				continue;
			var area_begin : u64 = @intCast(ft.mem.alignForward(u64, e.base, page_size));
			var area_end : u64 = @intCast(ft.mem.alignBackward(u64, e.base + e.length, page_size));
			if (area_end > pageFrameAllocator.total_space)
				area_end = @intCast(ft.mem.alignBackward(u64, pageFrameAllocator.total_space, page_size));
			if (area_begin >= area_end) // smaller than a page
				continue;
			while (area_begin < area_end) : (area_begin += page_size) {
				if (area_begin < @intFromPtr(boot.kernel_end)) // area is before kernel end
					continue;
				pageFrameAllocator.free_pages(@truncate(area_begin), 1) catch @panic("cannot init page frame allocator");
			}
		}
	}
}

fn get_max_mem() u64 {
	if (multiboot.get_tag(multiboot2_h.MULTIBOOT_TAG_TYPE_BASIC_MEMINFO)) |meminfo| {
		return meminfo.mem_upper * 1000;
	} else @panic("no meminfo tag in multiboot");
}
