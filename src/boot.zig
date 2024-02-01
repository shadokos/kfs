const kernel_main = @import("kernel.zig").kernel_main;
const multiboot2_h = @import("c_headers.zig").multiboot2_h;
const multiboot = @import("multiboot.zig");

export const STACK_SIZE: u32 = 16 * 1024;

export var stack: [STACK_SIZE]u8 align(16) linksection(".bss") = undefined;

export var multiboot_header : multiboot.header_type align(4) linksection(".multiboot") = multiboot.get_header();

export fn _entry() callconv(.Naked) noreturn {
	asm volatile(
		\\ mov $stack, %esp
		\\ add STACK_SIZE, %esp
		\\ movl %esp, %ebp
		\\ movl %ebx, multiboot_info
		\\ call init
	);
	while (true) {}
}

pub export var multiboot_info : * volatile multiboot.multiboot_info = undefined;

export fn init() void {
	kernel_main();
}
