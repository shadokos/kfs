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

pub const ft_options : @import("ft/ft.zig").Options = .{
	.log_level = .warn,
	.logFn = @import("logger.zig").kernel_log,
	// .log_scope_levels = &.{},
};

export fn _entry() linksection(".bootstrap_code") callconv(.Naked) noreturn {
	_ = @import("trampoline.zig");
	asm volatile(
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

comptime {
	_ = @import("trampoline.zig");
}

export fn init(eax : u32, ebx : u32) callconv(.C) void {
	if (eax == multiboot2_h.MULTIBOOT2_BOOTLOADER_MAGIC) {
		multiboot_info = @ptrFromInt(paging.low_half + ebx); // TODO!
	} else @panic("No multiboot2 magic number");

	@import("trampoline.zig").clean();

	@import("tty/tty.zig").init();

	@import("memory.zig").init();

	@import("gdt.zig").setup();

	multiboot_info = multiboot.map(ebx);

	@import("drivers/ps2/ps2.zig").init();

	@import("./drivers/acpi/acpi.zig").init();

	kernel.main();
}

pub fn panic(msg: []const u8, _: ?*builtin.StackTrace, _: ?usize) noreturn {
	@import("ft/ft.zig").log.err("{s}", .{msg});
	while (true) {}
}
