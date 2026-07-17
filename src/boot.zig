const std = @import("std");
const kernel = @import("kernel.zig");
const multiboot2_h = @import("c_headers.zig").multiboot2_h;
const multiboot = @import("multiboot.zig");
const builtin = std.builtin;
const paging = @import("memory/paging.zig");
const mapping = @import("memory/mapping.zig");
const log = std.log;

// Stack pages + 1 guard page if debug build (to catch stack overflows during boot phase)
const STACK_PAGES: u32 = 8;
const STACK_SIZE: u32 = STACK_PAGES * paging.page_size;

var stack: [STACK_SIZE]u8 align(4096) linksection(".bss") = undefined;

export var stack_bottom: [*]u8 = @as([*]u8, @ptrCast(&stack)) + @sizeOf(@TypeOf(stack));

// Address of the boot stack guard page (first page of the stack array).
// Used by the double fault handler to detect stack overflow during boot phase.
pub const boot_stack_guard_page: paging.VirtualPagePtr = @ptrCast(&stack);

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
}

export fn init(eax: u32, ebx: u32) callconv(.c) noreturn {
    @import("task/scheduler.zig").enter_critical();

    if (eax == multiboot2_h.MULTIBOOT2_BOOTLOADER_MAGIC) {
        multiboot_info = @ptrFromInt(paging.high_half + ebx); // TODO!
    } else @panic("No multiboot2 magic number");

    @import("trampoline.zig").clean();

    init_hardware();
    init_subsystems();
    init_tasks(); // does not return, switches to idle task stack
}

/// Low-level CPU, chipset and memory initialization.
fn init_hardware() void {
    @import("tty/tty.zig").init();
    log.info("Terminal initialized", .{});

    @import("gdt.zig").init();
    @import("drivers/pic/pic.zig").init();

    // Sets up the IDT, and unlocks the scheduler (decrements lock_depth, enables interrupts)
    @import("interrupts.zig").init();

    @import("memory.zig").init();
    @import("debug.zig").init();

    if (@import("build_options").optimize == .Debug) {
        mapping.clear_present(boot_stack_guard_page);
    }

    @import("drivers/tsc/tsc.zig").init();
    @import("timer.zig").init();
}

/// Drivers, kernel services and device initialization.
fn init_subsystems() void {
    @import("drivers/ps2/ps2.zig").init();
    @import("tty/keyboard.zig").init();
    @import("./drivers/acpi/acpi.zig").init();
    @import("syscall.zig").init();

    @import("task/signal.zig").SignalQueue.init_cache() catch @panic("Failed to initialize SignalQueue cache");

    // The ready_queue and wait_queue init functions are only here to setup their on_terminate task callbacks
    @import("task/ready_queue.zig").init();
    @import("task/wait_queue.zig").init();

    @import("device/block/registry.zig").init();
    @import("device/char/registry.zig").init();
    @import("drivers/char/mem.zig").init();

    @import("drivers/pci/pci.zig").init() catch @panic("Failed to initialize PCI subsystem");
    @import("drivers/ide/ide.zig").init() catch @panic("Failed to initialize IDE subsystem");

    @import("drivers/block/ramdisk.zig").init();
    @import("drivers/block/ide_hd.zig").init();
}

/// Bootstrap the task system: create idle task, switch to its stack, spawn the kernel main task.
/// Does not return, the boot stack is abandoned here.
fn init_tasks() noreturn {
    const task_set = @import("task/task_set.zig");
    const scheduler = @import("task/scheduler.zig");
    const gdt = @import("gdt.zig");

    const idle_task = task_set.create_task() catch @panic("Failed to create idle task");
    scheduler.init(idle_task);

    // Switch to the idle task's own stack. After this point the boot stack is dead.
    gdt.tss.esp0 = idle_task.stack_top();
    gdt.flush();
    asm volatile (
        \\ mov %[esp], %%esp
        \\ mov %[esp], %%ebp
        :
        : [esp] "r" (idle_task.stack_top()),
    );

    const kernel_task = task_set.create_task() catch @panic("Failed to create kernel task");
    const main = if (!@import("build_options").ci) kernel.main else @import("ci.zig").main;
    kernel_task.spawn(main, undefined) catch @panic("Failed to spawn kernel main task");

    while (true) {
        @import("cpu.zig").halt();
    }
}

pub fn panic(msg: []const u8, _: ?*builtin.StackTrace, ret_addr: ?usize) noreturn {
    // Point the backtrace at the code that called @panic
    const first_addr = ret_addr orelse @returnAddress();
    @import("logger.zig").panic_trace_override = std.debug.StackIterator.init(first_addr, @frameAddress());
    log.err("{s}", .{msg});
    unreachable;
}
