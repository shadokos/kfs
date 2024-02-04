const ft = @import("../ft/ft.zig");
const tty = @import("../tty/tty.zig");
const helpers = @import("helpers.zig");
const utils = @import("utils.zig");
const CmdError = @import("../shell.zig").CmdError;

pub fn stack(_: anytype) CmdError!void {
	if (@import("build_options").optimize != .Debug) {
		utils.print_error("{s}", .{"The stack builtin is only available in debug mode"});
		return CmdError.OtherError;
	}
	utils.dump_stack();
	utils.print_stack();
}

fn _help_available_commands() void {
	tty.printk(utils.blue ++ "Available commands:\n" ++ utils.reset, .{});
	inline for (@typeInfo(@This()).Struct.decls) |decl| {
		tty.printk("  - {s}\n", .{decl.name});
	}
}

pub fn help(data: [][]u8) CmdError!void {
	if (data.len <= 1)  {
		_help_available_commands();
		return;
	}
	inline for (@typeInfo(helpers).Struct.decls) |decl| {
		if (ft.mem.eql(u8, decl.name, data[1])) {
			@field(helpers, decl.name)();
			return;
		}
	}
	utils.print_error("There's no help page for \"{s}\"\n", .{data[1]});
	_help_available_commands();
	return CmdError.OtherError;
}

pub fn clear(_: [][]u8) CmdError!void {
	tty.printk("\x1b[2J\x1b[H", .{});
	return;
}

pub fn hexdump(args: [][]u8) CmdError!void {
	if (args.len != 3) {
		return CmdError.InvalidNumberOfArguments;
	}
	var begin : usize = ft.fmt.parseInt(usize, args[1], 0) catch return CmdError.InvalidParameter;
	var len : usize = ft.fmt.parseInt(usize, args[2], 0) catch return CmdError.InvalidParameter;
	utils.memory_dump(begin, begin +| len);
}

pub fn mmap(_: [][]u8) CmdError!void {
	utils.print_mmap();
}

pub fn keymap(args: [][]u8) CmdError!void {
	const km = @import("../tty/keyboard/keymap.zig");
	switch(args.len) {
		1 => {
			const list = km.keymap_list;
			tty.printk("Installed keymaps:\n\n", .{});
			for (list) |e| {
				tty.printk(" - {s}\n", .{e});
			}
			tty.printk("\n", .{});
		},
		2 => km.set_keymap(args[1]) catch return CmdError.InvalidParameter,
		else => return CmdError.InvalidNumberOfArguments
	}
}

pub fn shutdown(_: [][]u8) CmdError!void {
	_ = @import("../drivers/acpi/acpi.zig").power_off();
	utils.print_error("Failed to shutdown\n", .{});
	return CmdError.OtherError;
}

pub fn reboot(_: [][]u8) CmdError!void {
	// Try to reboot using PS/2 Controller
	@import("../drivers/ps2/ps2.zig").cpu_reset();

	// If it fails, try the page fault method
	asm volatile ("jmp 0xFFFF");

	utils.print_error("Reboot failed", .{});
	return CmdError.OtherError;
}