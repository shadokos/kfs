const kernel = @import("kernel.zig");
const multiboot2_h = @import("c_headers.zig").multiboot2_h;
const multiboot = @import("multiboot.zig");
const builtin = @import("std").builtin;
const paging = @import("memory/paging.zig");

const STACK_SIZE: u32 = 16 * 16 * 1024;

var stack: [STACK_SIZE]u8 align(4096) linksection(".bss") = undefined;

export var stack_bottom : [*]u8 = @as([*]u8, @ptrCast(&stack)) + @sizeOf(@TypeOf(stack));

export var multiboot_header : multiboot.header_type align(4) linksection(".multiboot") = multiboot.get_header();

pub const kernel_end = @extern([*]u8, .{.name = "kernel_end"});

pub var multiboot_info : *multiboot.info_header = undefined;

export fn _entry() linksection(".bootstrap_code") callconv(.Naked) noreturn {
	asm volatile(
		\\ mov $stack_bottom, %esp
		\\ sub $0xc0000000, %esp
		\\ mov (%esp), %esp
		\\ sub $0xc0000000, %esp
		\\ movl %esp, %ebp
		\\ push %ebx
		\\ push %eax
		\\ call trampoline_jump
		\\ add $0xc0000000, %esp
		\\ call init
	);
	while (true) {}
}

comptime {
	_ = @import("trampoline.zig");
}

export fn init(eax : u32, ebx : u32) callconv(.C) void {
	if (eax == multiboot2_h.MULTIBOOT2_BOOTLOADER_MAGIC) {
		multiboot_info = @ptrFromInt(paging.low_half + ebx);
	} else @panic("No multiboot2 magic number");

	@import("gdt.zig").setup();
	@import("memory.zig").init();

	multiboot_info = multiboot.map(ebx);

	@import("drivers/ps2/ps2.zig").init();
	// @import("./drivers/acpi/acpi.zig").init();

	kernel.main();
}

pub fn panic(msg: []const u8, _: ?*builtin.StackTrace, _: ?usize) noreturn {
	const tty = @import("tty/tty.zig");
	const utils = @import("shell/utils.zig");

	tty.printk("{s}@ Kernel Panic\n{s}\n", .{
		utils.red, msg
	});
	while (true) {}
}
