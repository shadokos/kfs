const ft = @import("../ft/ft.zig");
const tty = @import("../tty/tty.zig");
const helpers = @import("helpers.zig");
const utils = @import("utils.zig");

pub fn stack(_: anytype) usize {
	var ebp: usize = @frameAddress();
	var esp: usize = 0;

	asm volatile("movl %esp, %[esp]" : [esp] "=r" (esp));
	utils.dump_stack(ebp, esp);
	utils.print_stack(ebp, esp);
	return 0;
}

fn _help_available_commands() void {
	tty.printk(utils.blue ++ "Available commands:\n" ++ utils.reset, .{});
	inline for (@typeInfo(@This()).Struct.decls) |decl| {
		tty.printk("  - {s}\n", .{decl.name});
	}
}

pub fn help(data: [][]u8) usize {
	if (data.len <= 1)  {
		_help_available_commands();
		return 0;
	}
	inline for (@typeInfo(helpers).Struct.decls) |decl| {
		if (ft.mem.eql(u8, decl.name, data[1])) {
			@field(helpers, decl.name)();
			return 0;
		}
	}
	tty.printk(
		utils.red ++
		"Error:" ++
		utils.reset ++
		" Help: There's no help page for \"{s}\"\n", .{ data[1] }
	);
	_help_available_commands();
	return 2;
}

pub fn clear(_: [][]u8) usize {
	tty.printk("\x1b[2J\x1b[H", .{});
	return 0;
}