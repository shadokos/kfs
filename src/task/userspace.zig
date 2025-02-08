const ft = @import("ft");
const gdt = @import("../gdt.zig");
const cpu = @import("../cpu.zig");
const memory = @import("../memory.zig");
const VirtualSpace = @import("../memory/virtual_space.zig").VirtualSpace;
const paging = @import("../memory/paging.zig");
const interrupts = @import("../interrupts.zig");
const scheduler = @import("scheduler.zig");

fn map_userspace(vm: *VirtualSpace) void {
    const up_start = ft.mem.alignBackward(u32, @intFromPtr(@extern(*u8, .{ .name = "userspace_start" })), 4096);
    const up_end = ft.mem.alignForward(u32, @intFromPtr(@extern(*u8, .{ .name = "userspace_end" })), 4096);

    vm.map(
        up_start,
        @ptrFromInt(up_start),
        (up_end - up_start) / paging.page_size,
    ) catch @panic("Failed to map userspace");
    VirtualSpace.make_present(
        @ptrFromInt(up_start),
        (up_end - up_start) / paging.page_size,
    ) catch unreachable;
}
comptime {
    _ = @import("../userspace.poc.zig");
}
extern fn _userland() void;

pub fn switch_to_userspace(_: anytype) u8 {
    clone(@intFromPtr(&_userland));
    return 0;
}

fn create_stack(vm: *VirtualSpace, size: usize) paging.VirtualPagePtr {
    return vm.alloc_pages(size) catch @panic("Failed to allocate user");
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
