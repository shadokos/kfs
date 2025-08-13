const std = @import("std");
const kernel = @import("kernel.zig");
const multiboot2_h = @import("c_headers.zig").multiboot2_h;
const multiboot = @import("multiboot.zig");
const builtin = std.builtin;
const paging = @import("memory/paging.zig");
const log = std.log;

const STACK_SIZE: u32 = 64 * 1024;

var stack: [STACK_SIZE]u8 align(4096) linksection(".bss") = undefined;

export var stack_bottom: [*]u8 = @as([*]u8, @ptrCast(&stack)) + @sizeOf(@TypeOf(stack));

export var multiboot_header: multiboot.header_type align(4) linksection(".multiboot") = multiboot.get_header();

pub const kernel_end = @extern([*]u8, .{ .name = "kernel_end" });

pub var multiboot_info: *multiboot.info_header = undefined;

pub const std_options: @import("std").Options = .{
    .logFn = @import("logger.zig").kernel_log,
    .log_level = switch (@import("build_options").optimize) {
        .Debug => log.Level.debug,
        else => log.Level.info,
    },
};

export fn _entry() linksection(".bootstrap_code") callconv(.naked) noreturn {
    _ = @import("trampoline.zig");
    asm volatile (
    // find physical address of stack bottom
        \\ mov $stack_bottom, %esp
        \\ sub $0xc0000000, %esp

        // load physical address of the bottom of the stack (value pointed by stack_bottom)
        \\ mov (%esp), %esp
        \\ sub $0xc0000000, %esp

        // set ebp
        \\ movl %esp, %ebp

        // preserve ebx and eax for init
        \\ push %ebx
        \\ push %eax

        // jump to low half
        \\ call trampoline_jump

        // now set the stack at its virtual address
        \\ add $0xc0000000, %esp
        \\ call init
    );
    while (true) {}
}

export fn init(eax: u32, ebx: u32) callconv(.c) void {
    // Locks the scheduler (disables interrupts, and increments lock_depth)
    @import("task/scheduler.zig").enter_critical();

    if (eax == multiboot2_h.MULTIBOOT2_BOOTLOADER_MAGIC) {
        multiboot_info = @ptrFromInt(paging.high_half + ebx); // TODO!
    } else @panic("No multiboot2 magic number");

    @import("trampoline.zig").clean();

    @import("tty/tty.zig").init();
    log.info("Terminal initialized", .{});

    @import("gdt.zig").init();

    @import("drivers/pic/pic.zig").init();

    // Sets up the IDT, and unlocks the scheduler (decrements lock_depth, and enables interrupts)
    @import("interrupts.zig").init();

    @import("memory.zig").init();

    @import("debug.zig").init();

    @import("timer.zig").init();

    @import("drivers/ps2/ps2.zig").init();

    @import("tty/keyboard.zig").init();

    @import("./drivers/acpi/acpi.zig").init();

    @import("syscall.zig").init();

    @import("task/task.zig").TaskDescriptor.init_cache() catch @panic("Failed to initialized task_descriptor cache");

    @import("task/signal.zig").SignalQueue.init_cache() catch @panic("Failed to initialized SignalQueue cache");

    @import("task/task.zig").TaskDescriptor.init_cache() catch @panic("Failed to initialized task_descriptor cache");

    // The ready_queue and wait_queue init functions are only here to setup their on_terminate task callbacks
    @import("task/ready_queue.zig").init();
    @import("task/wait_queue.zig").init();

    const idle_task = @import("task/task_set.zig").create_task() catch @panic("Failed to create idle task");

    @import("task/scheduler.zig").init(idle_task);

    const kernel_task = @import("task/task_set.zig").create_task() catch @panic("Failed to create kernel task");

    const main = if (!@import("build_options").ci) kernel.main else @import("ci.zig").main;
    kernel_task.spawn(main, undefined) catch @panic("Failed to spawn kernel main task");

    while (true) {
        @import("cpu.zig").halt();
    }
}

pub fn panic(msg: []const u8, _: ?*builtin.StackTrace, _: ?usize) noreturn {
    log.err("{s}", .{msg});
    unreachable;
}
