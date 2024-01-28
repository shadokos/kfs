const kernel_main = @import("kernel.zig").kernel_main;
const multiboot_h = @import("c_headers.zig").multiboot_h;

export const STACK_SIZE: u32 = 16 * 1024;

export var stack: [STACK_SIZE]u8 align(16) linksection(".bss") = undefined;

fn get_header() multiboot_h.multiboot_header {
	var ret : multiboot_h.multiboot_header = undefined;

	ret.magic = multiboot_h.MULTIBOOT_HEADER_MAGIC;
	ret.flags = multiboot_h.MULTIBOOT_PAGE_ALIGN | multiboot_h.MULTIBOOT_MEMORY_INFO;

	ret.checksum = @bitCast(-(@as(i32, ret.magic) + @as(i32, ret.flags)));
	return ret;
}

export var multiboot : multiboot_h.multiboot_header align(4) linksection(".multiboot") = get_header();

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

pub export var multiboot_info : * volatile multiboot_h.multiboot_info_t = undefined;

export fn init() void {
	kernel_main();
}
