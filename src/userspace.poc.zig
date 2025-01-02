const ft = @import("ft");
const memory = @import("memory.zig");

const VirtualSpace = @import("memory/virtual_space.zig").VirtualSpace;
const paging = @import("memory/paging.zig");

export var task_stack: [32 * paging.page_size]u8 align(paging.page_size) = undefined;

pub fn init_vm() !*VirtualSpace {
    const vm = try memory.virtualMemory.allocator().create(VirtualSpace);
    try vm.init();
    try vm.add_space(0, paging.high_half / paging.page_size);
    try vm.add_space((paging.page_tables) / paging.page_size, 768);
    vm.transfer();
    try vm.fill_page_tables(paging.page_tables / paging.page_size, 768, false);
    return vm;
}

pub const SigHandler = *fn () void;

var current_signal: ?SigHandler = null;

pub fn queue_signal(handler: SigHandler) void {
    current_signal = handler;
}

pub fn get_next_signal() ?SigHandler {
    defer current_signal = null;
    return current_signal;
}

fn poc_signal() linksection("userspace") void {
    const str = "Signal handled\n";
    _ = syscall(.write, .{ str, str.len });
}

pub fn switch_to_userspace(_: anytype) u8 {
    @import("gdt.zig").tss.esp0 = @as(usize, @intFromPtr(&task_stack)) + task_stack.len;

    const vm = init_vm() catch @panic("Failed to initialize userspace");

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

    const stack = vm.alloc_pages(4) catch @panic("Failed to allocate user");
    VirtualSpace.make_present(stack, 4) catch unreachable;

    const stack_segment: u32 = @intCast(@import("gdt.zig").get_selector(6, .GDT, .User));
    const code_segment: u32 = @intCast(@import("gdt.zig").get_selector(4, .GDT, .User));

    @import("cpu.zig").set_esp(@as(u32, @intFromPtr(stack)) + paging.page_size);
    asm volatile (
        \\ push %[ss]
        \\ push %[esp]
        \\ push $0x200
        \\ push %[cs]
        \\ push %[function]
        \\ iret
        :
        : [ss] "r" (stack_segment),
          [esp] "r" (@as(u32, @intFromPtr(stack)) + (paging.page_size * 4)),
          [cs] "r" (code_segment),
          [function] "r" (&_userland),
    );
    return 0;
}

pub fn syscall(code: anytype, args: anytype) linksection(".userspace") i32 {
    const _code: u32 = switch (@typeInfo(@TypeOf(code))) {
        .@"enum", .enum_literal => @intFromEnum(@as(@import("syscall.zig").Code, code)),
        .int, .comptime_int => @intCast(code),
        else => @compileError("Invalid syscall code type"),
    };

    var _args: struct { ebx: i32 = 0, ecx: i32 = 0, edx: i32 = 0, esi: i32 = 0, edi: i32 = 0 } = .{};

    const regs = .{ "ebx", "ecx", "edx", "esi", "edi" };
    inline for (args, 0..) |arg, i| {
        @field(_args, regs[i]) = switch (@typeInfo(@TypeOf(arg))) {
            .int, .comptime_int => @intCast(arg),
            .pointer => @bitCast(@as(u32, @intFromPtr(arg))),
            else => @compileError("Invalid syscall argument type"),
        };
    }

    var ebx: u32 = 0;
    const res: i32 = @bitCast(asm volatile ("int $0x80"
        : [_] "={ebx}" (ebx),
          [_] "={eax}" (-> i32),
        : [_] "{eax}" (_code),
          [_] "{ebx}" (_args.ebx),
          [_] "{ecx}" (_args.ecx),
          [_] "{edx}" (_args.edx),
          [_] "{esi}" (_args.esi),
          [_] "{edi}" (_args.edi),
    ));
    if (ebx != 0) return -1;
    return res;
}

export fn _userland() linksection(".userspace") void {
    for (0..9) |i| {
        if (i % 3 == 0) _ = syscall(.poc_raise, .{&poc_signal});
        _ = syscall(.write, &.{ "write from userspace\n", 21 });
        _ = syscall(.sleep, .{1000});
    }
    _ = syscall(.reboot, .{});
}
