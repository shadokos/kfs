const kernel_main = @import("kernel.zig").kernel_main;
const multiboot2_h = @import("c_headers.zig").multiboot2_h;
const multiboot = @import("multiboot.zig");
const builtin = @import("std").builtin;

const STACK_SIZE: u32 = 16 * 1024;

var stack: [STACK_SIZE]u8 align(4096) linksection(".bss") = undefined;

export var stack_bottom : [*]u8 = @as([*]u8, @ptrCast(&stack)) + @sizeOf(@TypeOf(stack));

export var multiboot_header : multiboot.header_type align(4) linksection(".multiboot") = multiboot.get_header();

export fn _entry() callconv(.Naked) noreturn {
	asm volatile(
		\\ mov stack_bottom, %esp
		\\ movl %esp, %ebp
		\\ movl %ebx, multiboot_info
		\\ call init
	);
	while (true) {}
}

pub export var multiboot_info : * volatile multiboot.info_header = undefined;

pub fn panic(msg: []const u8, _: ?*builtin.StackTrace, _: ?usize) noreturn {
	const tty = @import("tty/tty.zig");

	tty.printk("panic: {s}\n", .{msg});
	while (true) {}
}

export fn init() void {
	kernel_main();
}
