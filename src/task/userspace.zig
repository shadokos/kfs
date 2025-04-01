const ft = @import("ft");
const gdt = @import("../gdt.zig");
const cpu = @import("../cpu.zig");
const memory = @import("../memory.zig");
const VirtualSpace = @import("../memory/virtual_space.zig").VirtualSpace;
const paging = @import("../memory/paging.zig");
const interrupts = @import("../interrupts.zig");
const scheduler = @import("scheduler.zig");
const RegionSet = @import("../memory/region_set.zig").RegionSet;
const regions = @import("../memory/regions.zig");

fn map_userspace(vm: *VirtualSpace) void {
    const up_start = ft.mem.alignBackward(u32, @intFromPtr(@extern(*u8, .{ .name = "userspace_start" })), 4096);
    const up_end = ft.mem.alignForward(u32, @intFromPtr(@extern(*u8, .{ .name = "userspace_end" })), 4096);

    const region = RegionSet.create_region() catch @panic("cannot map userspace");
    errdefer RegionSet.destroy_region(region) catch unreachable;

    region.flags = .{
        .read = true,
        .write = true,
        .may_read = true,
        .may_write = true,
    };

    regions.PhysicalMapping.init(region, 0);

    vm.add_region_at(
        region,
        up_start / paging.page_size,
        (up_end - up_start) / paging.page_size,
        true,
    ) catch @panic("cannot map userspace");
}
comptime {
    _ = @import("../userspace.poc.zig");
}

pub fn call_userspace(f: usize) u8 {
    clone(f);
    return 0;
}

fn create_stack(vm: *VirtualSpace, size: usize) paging.VirtualPagePtr {
    const region = RegionSet.create_region() catch @panic("cannot map userspace");
    errdefer RegionSet.destroy_region(region) catch unreachable;

    region.flags = .{
        .read = true,
        .write = true,
        .may_read = true,
        .may_write = true,
    };

    regions.VirtuallyContiguousRegion.init(region, .{
        .private = true,
    });

    vm.add_region(region, size) catch @panic("cannot map userspace");

    return @ptrFromInt(region.begin * paging.page_size);
}

pub fn clone(entrypoint: usize) noreturn {
    const task = scheduler.get_current_task();
    task.init_vm() catch @panic("todo Failed to initialize userspace");

    const vm = task.vm.?;

    map_userspace(vm);

    const stack_size: usize = 8; // todo: get this from config (static or dynamic)
    const stack = create_stack(vm, stack_size);

    const frame = interrupts.InterruptFrame{
        .edi = 0,
        .esi = 0,
        .ebp = 0,
        .edx = 0,
        .ecx = 0,
        .ebx = 0,
        .eax = 0,
        .code = 0,
        .iret = .{
            .ip = entrypoint,
            .cs = .{ .index = 4, .table = .GDT, .privilege = .User },
            .flags = @bitCast(cpu.EFlags{ .interrupt_enable = true }),
            .sp = @as(u32, @intFromPtr(stack)) + (paging.page_size * stack_size),
            .ss = .{ .index = 6, .table = .GDT, .privilege = .User },
        },
    };

    interrupts.ret_from_interrupt(&frame);
}
