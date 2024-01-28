comptime { _ = @import("kernel.zig"); }

export const STACK_SIZE: u32 = 16 * 1024;
const ALIGN = 1 << 0;
const MEMINFO = 1 << 1;
const MAGIC : i32 = 0x1BADB002;
const FLAGS : i32 = ALIGN | MEMINFO;

export var stack: [STACK_SIZE]u8 align(16) linksection(".bss") = undefined;

const multiboot_t = extern struct {
	magic: i32,
	flags: i32,
	checksum: i32,
};

export var multiboot : multiboot_t align(4) linksection(".multiboot") = .{
	.magic = MAGIC,
	.flags = FLAGS,
	.checksum = -(MAGIC + FLAGS)
};

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

const multiboot_h = @import("c_headers.zig").multiboot_h;

pub export var multiboot_info : * volatile multiboot_h.multiboot_info_t = undefined;

extern fn kernel_main() void;

export fn init() void {
	kernel_main();
}
