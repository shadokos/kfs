const kernel = @import("kernel.zig");
const multiboot2_h = @import("c_headers.zig").multiboot2_h;
const multiboot = @import("multiboot.zig");
const builtin = @import("std").builtin;

const STACK_SIZE: u32 = 16 * 1024;

var stack: [STACK_SIZE]u8 align(4096) linksection(".bss") = undefined;

export var stack_bottom : [*]u8 = @as([*]u8, @ptrCast(&stack)) + @sizeOf(@TypeOf(stack));

export var multiboot_header : multiboot.header_type align(4) linksection(".multiboot") = multiboot.get_header();

pub var multiboot_info : *multiboot.info_header = undefined;

export fn _entry() callconv(.Naked) noreturn {
	asm volatile(
		\\ mov stack_bottom, %esp
		\\ movl %esp, %ebp
		\\ push %ebx
		\\ push %eax
		\\ call init
	);
	while (true) {}
}

export fn init(eax : u32, ebx : *multiboot.info_header) void {
	if (eax == multiboot2_h.MULTIBOOT2_BOOTLOADER_MAGIC) {
		multiboot_info = ebx;
	} else @panic("No multiboot2 magic number");

	@import("gdt.zig").setup();
	@import("drivers/ps2/ps2.zig").init();
	_ = @import("./drivers/acpi/acpi.zig").init();

	kernel.main();
}

pub fn panic(msg: []const u8, _: ?*builtin.StackTrace, _: ?usize) noreturn {
	const tty = @import("tty/tty.zig");

	tty.printk("panic: {s}\n", .{msg});
	while (true) {}
}
