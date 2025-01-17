const ft = @import("ft");
const gdt = @import("../gdt.zig");
const cpu = @import("../cpu.zig");
const memory = @import("../memory.zig");
const VirtualSpace = @import("../memory/virtual_space.zig").VirtualSpace;
const paging = @import("../memory/paging.zig");
const interrupts = @import("../interrupts.zig");

pub fn init_vm() !*VirtualSpace {
    const vm = try memory.bigAlloc.allocator().create(VirtualSpace);
    try vm.init();
    try vm.add_space(0, paging.high_half / paging.page_size);
    try vm.add_space((paging.page_tables) / paging.page_size, 768);
    vm.transfer();
    try vm.fill_page_tables(paging.page_tables / paging.page_size, 768, false);
    return vm;
}

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

fn create_stack(vm: *VirtualSpace, size: usize) paging.VirtualPagePtr {
    const stack = vm.alloc_pages(size) catch @panic("Failed to allocate user");
    VirtualSpace.make_present(stack, size) catch unreachable;
    return stack;
}

extern fn _userland() void;

pub fn switch_to_userspace(_: anytype) u8 {
    const vm = init_vm() catch @panic("Failed to initialize userspace");

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
            .ip = @intFromPtr(&_userland),
            .cs = @intCast(gdt.get_selector(4, .GDT, .User)),
            .flags = @bitCast(cpu.EFlags{
                .interrupt_enable = true,
            }),
            .sp = @as(u32, @intFromPtr(stack)) + (paging.page_size * stack_size),
            .ss = @intCast(gdt.get_selector(6, .GDT, .User)),
        },
    };

    interrupts.ret_from_interrupt(&frame);
    return 0;
}
