const boot = @import("boot.zig");
const interrupts = @import("interrupts.zig");
const ft = @import("ft");
const tty = @import("./tty/tty.zig");
const printk = @import("./tty/tty.zig").printk;
const PageFrameAllocator = @import("memory/page_frame_allocator.zig").PageFrameAllocator;
const DirectPageAllocator = @import("memory/direct_page_allocator.zig").DirectPageAllocator;
const paging = @import("memory/paging.zig");
const multiboot = @import("multiboot.zig");
const multiboot2_h = @import("c_headers.zig").multiboot2_h;
const mapping = @import("memory/mapping.zig");
const logger = @import("ft").log.scoped(.memory);
const VirtualSpace = @import("memory/virtual_space.zig").VirtualSpace;

const StaticAllocator = @import("memory/object_allocators/static_allocator.zig").StaticAllocator;
const PageGrainedAllocator = @import("memory/object_allocators/page_grained_allocator.zig").PageGrainedAllocator;
const MultipoolAllocator = @import("memory/object_allocators/multipool_allocator.zig").MultipoolAllocator;

const PageFrameAllocatorType = PageFrameAllocator(enum {
    Medium,
    Direct,
});

pub var pageFrameAllocator: PageFrameAllocatorType = .{};

pub var kernel_virtual_space: VirtualSpace = undefined;

pub var globalCache: @import("memory/object_allocators/slab/cache.zig").GlobalCache = undefined;

// ======= page allocators =======
pub var directPageAllocator: DirectPageAllocator = undefined;
pub var physically_contiguous_page_allocator = kernel_virtual_space.generate_page_allocator(.{
    .immediate_mapping = true,
    .physically_contiguous = true,
});
pub var virtually_contiguous_page_allocator = kernel_virtual_space.generate_page_allocator(.{
    .immediate_mapping = true,
    .physically_contiguous = false,
});
//  =================================

// ======= object allocators =======
pub var boot_allocator: StaticAllocator(
    PageFrameAllocatorType.UnderlyingAllocator.size_for(paging.direct_zone_size / paging.page_size),
) = .{};
pub var bigAlloc: PageGrainedAllocator = undefined;
pub var smallAlloc: MultipoolAllocator = undefined;
pub var directMemory: MultipoolAllocator = undefined;
//  =================================

const InterruptFrame = @import("interrupts.zig").InterruptFrame;

fn GPE_handler(frame: InterruptFrame) void {
    logger.err("general protection fault 0b{b:0>32}", .{frame.code});
}

fn init_PFA(direct_begin: paging.PhysicalPtr, direct_size: paging.PhysicalUsize, total_space: u64) void {
    logger.debug("\tInitializing page frame allocator...", .{});
    pageFrameAllocator = PageFrameAllocatorType.init(total_space);
    pageFrameAllocator.init_zone(
        .Direct,
        direct_begin,
        direct_size,
        boot_allocator.allocator(),
    );
    logger.debug("\tPage frame allocator initialized", .{});
}

fn init_medium(medium_begin: paging.PhysicalPtr, medium_size: paging.PhysicalUsize) void {
    logger.debug("\tInitializing medium physical memory (from 0x{x:0>8} to 0x{x:0>8})...", .{
        medium_begin,
        medium_begin + medium_size,
    });
    pageFrameAllocator.init_zone(
        .Medium,
        medium_begin,
        medium_size,
        bigAlloc.allocator(),
    );
    check_mem_availability(medium_begin, medium_begin + medium_size); // todo: maybe find a faster way
    logger.debug("\tMedium physical memory initialized...", .{});
}

fn init_physical_memory() void {
    logger.debug("\tInitializing physical memory allocator...", .{});
    directMemory = MultipoolAllocator.init("dma_kmalloc", directPageAllocator.page_allocator()) catch {
        @panic("cannot cache_init MultipoolAllocator");
    };
    smallAlloc = MultipoolAllocator.init("kmalloc", virtually_contiguous_page_allocator.page_allocator()) catch {
        @panic("cannot cache_init MultipoolAllocator");
    };
    logger.debug("\tPhysical memory allocator initialized", .{});
}

fn init_kernel_vm() void {
    logger.debug("\tInitializing kernel virtual space...", .{});
    VirtualSpace.global_init() catch @panic("unable to init VirtualSpace");
    kernel_virtual_space.init() catch @panic("unable to init kernel virtual space");
    const vm_begin = ft.mem.alignForward(usize, paging.high_half + @intFromPtr(boot.kernel_end), paging.page_size);
    const vm_end = paging.page_tables;
    kernel_virtual_space.add_space(
        vm_begin / paging.page_size,
        @intCast(vm_end / paging.page_size - vm_begin / paging.page_size),
    ) catch @panic("unable to init kernel virtual space");
    kernel_virtual_space.add_space(
        (paging.kernel_page_tables) / paging.page_size,
        256,
    ) catch @panic("unable to init kernel virtual space");
    logger.debug("\tKernel virtual space initialized", .{});

    logger.debug("\tEnabling interrupts...", .{});
    VirtualSpace.set_handler();
    interrupts.set_intr_gate(.GeneralProtectionFault, interrupts.Handler.create(&GPE_handler, true));
    logger.debug("\tInterrupts enabled...", .{});

    logger.debug("\tActivating kernel virtual space...", .{});
    kernel_virtual_space.transfer();
    kernel_virtual_space.fill_page_tables(paging.kernel_page_tables / paging.page_size, 256, true) catch {
        @panic("not enough space to boot");
    };
    logger.debug("\tKernel virtual space activated", .{});
}

pub fn init() void {
    logger.debug("Initializing memory", .{});

    const total_space: u64 = get_max_mem();
    logger.debug("\ttotal_space: {x}", .{total_space});

    const direct_begin: paging.PhysicalPtr = ft.mem.alignForward(
        paging.PhysicalPtr,
        @intFromPtr(boot.kernel_end),
        paging.page_size,
    );
    const direct_end: paging.PhysicalUsize = @max(direct_begin, ft.mem.alignBackward(
        paging.PhysicalPtr,
        @min(total_space, direct_begin + paging.direct_zone_size),
        paging.page_size,
    ));
    const direct_size: paging.PhysicalUsize = direct_end - direct_begin;

    const medium_begin: paging.PhysicalPtr = ft.mem.alignForward(paging.PhysicalPtr, direct_end, paging.page_size);
    const medium_end: paging.PhysicalPtr = @max(medium_begin, ft.mem.alignBackward(
        paging.PhysicalPtr,
        @min(total_space, paging.kernel_virtual_space_top),
        paging.page_size,
    ));
    const medium_size: paging.PhysicalUsize = medium_end - medium_begin;

    init_PFA(direct_begin, direct_size, total_space);

    logger.debug("\tCheck ram availability", .{});
    check_mem_availability(direct_begin, direct_end); // todo: maybe find a faster way

    logger.debug("\tInitializing direct page allocator...", .{});
    directPageAllocator = DirectPageAllocator.init(paging.high_half);

    logger.debug("\tInitializing slab allocator's global cache...", .{});
    const GlobalCache = @import("memory/object_allocators/slab/cache.zig").GlobalCache;
    globalCache = GlobalCache.init(directPageAllocator.page_allocator()) catch @panic("cannot init globalCache");
    logger.debug("\tGlobal cache initialized", .{});

    init_physical_memory();

    init_kernel_vm();

    // logger.debug("\tRemapping kernel...", .{});
    // map_kernel(); // todo shrink kernel
    // logger.debug("\tKernel remapped", .{});

    logger.debug("\tInitializing virtual memory allocator...", .{});
    bigAlloc = PageGrainedAllocator.init(virtually_contiguous_page_allocator.page_allocator());
    logger.debug("\tVirtual memory allocator initialized", .{});

    if (medium_size != 0) {
        init_medium(medium_begin, medium_size);
    }

    logger.info("Memory initialized", .{});
}

fn check_mem_availability(min: paging.PhysicalPtr, max: paging.PhysicalPtr) void {
    const page_size = @sizeOf(paging.page);
    if (multiboot.get_tag(multiboot2_h.MULTIBOOT_TAG_TYPE_MMAP)) |t| {
        var iter = multiboot.mmap_it{ .base = t };
        while (iter.next()) |e| {
            if (e.type != multiboot2_h.MULTIBOOT_MEMORY_AVAILABLE)
                continue;
            var area_begin: paging.PhysicalPtr = @intCast(
                ft.mem.alignForward(
                    paging.PhysicalPtr,
                    @as(paging.PhysicalPtr, @truncate(@min(e.base, (1 << 32) - 1))),
                    page_size,
                ),
            );
            var area_end: paging.PhysicalPtr = @intCast(
                ft.mem.alignBackward(
                    paging.PhysicalPtr,
                    @as(paging.PhysicalPtr, @truncate(@min(e.base + e.length, (1 << 32) - 1))),
                    page_size,
                ),
            );
            if (area_begin < min)
                area_begin = ft.mem.alignForward(paging.PhysicalPtr, min, page_size);
            if (area_end > max)
                area_end = ft.mem.alignBackward(paging.PhysicalPtr, max, page_size);
            if (area_begin >= area_end) // smaller than a page
                continue;
            while (area_begin < area_end) : (area_begin += page_size) {
                pageFrameAllocator.free_pages(
                    @truncate(area_begin),
                    1,
                ) catch @panic("cannot init page frame allocator");
            }
        }
    }
}

fn get_max_mem() u64 {
    if (multiboot.get_tag(multiboot2_h.MULTIBOOT_TAG_TYPE_BASIC_MEMINFO)) |meminfo| {
        return meminfo.mem_upper * 1000;
    } else @panic("no meminfo tag in multiboot");
}
