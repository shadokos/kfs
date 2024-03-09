const tty = @import("../tty/tty.zig");
const u = @import("utils.zig");

const Help = struct {
	name:  [:0]const u8,
	description: [:0]const u8,
	usage: ?[:0]const u8 = null
};

fn print_helper(h: Help) void {
	tty.printk(u.blue ++ "Command" ++ u.reset ++ ": {s}\n",  .{
		h.name
	});
	tty.printk(u.blue ++ "Description" ++ u.reset ++ ": {s}\n",  .{
		h.description
	});
	if (h.usage) |usage| {
		tty.printk(u.blue ++ "Usage" ++ u.reset ++ ": {s}\n",  .{usage});
	}
}

pub fn stack() void {
	print_helper(Help{
		.name = "stack",
		.description = "Display ebp traceback and dump the stack frames",
		.usage = null
	});
}

pub fn help() void {
	print_helper(Help{
		.name = "help",
		.description = "Prints the help message",
		.usage = "help <command>"
	});
}

pub fn clear() void {
	print_helper(Help{
		.name = "clear",
		.description = "Clears the screen",
		.usage = null
	});
}

pub fn hexdump() void {
	print_helper(Help{
		.name = "hexdump",
		.description = "Dump memory",
		.usage = "hexdump <base> <length>"
	});
}

pub fn mmap() void {
	print_helper(Help{
		.name = "mmap",
		.description = "Show multiboot2 mmap tag content",
		.usage = null
	});
}

pub fn keymap() void {
	print_helper(Help{
		.name = "keymap",
		.description = "Set keymap or list installed keymaps",
		.usage = "keymap [<name>]"
	});
}


pub fn theme() void {
	print_helper(Help{
		.name = "theme",
		.description = "Set theme or list available themes",
		.usage = "theme [<name>]"
	});
}

pub fn reboot() void {
	print_helper(Help{
		.name = "reboot",
		.description = "Reboot the system",
		.usage = null
	});
}

pub fn shutdown() void {
	print_helper(Help{
		.name = "shutdown",
		.description = "Shutdown the system",
		.usage = null
	});
}

pub fn kfuzz() void {
	print_helper(Help{
		.name = "kfuzz",
		.description = "fuzz the kernel memory allocator, do n iterations and allocate chunks of at most `max_size`",
		.usage = "kfuzz <n> [<max_size>]",
	});
}

pub fn vfuzz() void {
	print_helper(Help{
		.name = "vfuzz",
		.description = "fuzz the virtual memory allocator, do n iterations and allocate chunks of at most `max_size`",
		.usage = "vfuzz <n> [<max_size>]",
	});
}