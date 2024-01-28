const tty = @import("../tty/tty.zig");

const Help = struct {
	name:  [:0]const u8,
	description: [:0]const u8,
	usage: ?[:0]const u8 = null
};

fn print_helper(h: Help) void {
	tty.printk("{s}Command:{s} {s}\n",  .{"\x1b[36m", "\x1b[0m", h.name});
	tty.printk("{s}Description:{s} {s}\n", .{"\x1b[36m", "\x1b[0m", h.description});
	if (h.usage != null) {
		tty.printk("{s}Usage:{s} {s}\n", .{"\x1b[36m", "\x1b[0m", h.usage.?});
	}
}

pub fn stack() void {
	print_helper(Help{
		.name = "stack",
		.description =
			"Prints the stack.\n" ++
			"\x1b[33mWARNING:\x1b[0m This command is not implemented yet.",
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