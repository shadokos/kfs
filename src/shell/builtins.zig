const ft = @import("../ft/ft.zig");
const tty = @import("../tty/tty.zig");
const helpers = @import("helpers.zig");
const utils = @import("utils.zig");

pub fn stack(_: anytype) usize {
	if (@import("build_options").optimize != .Debug) {
		utils.print_error("{s}", .{"The stack builtin is only available in debug mode"});
		return 2;
	}
	utils.dump_stack();
	utils.print_stack();
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
	utils.print_error("There's no help page for \"{s}\"\n", .{data[1]});
	_help_available_commands();
	return 2;
}

pub fn clear(_: [][]u8) usize {
	tty.printk("\x1b[2J\x1b[H", .{});
	return 0;
}

pub fn hexdump(args: [][]u8) usize {
	if (args.len != 3)
	{
		utils.print_error("{s}", .{"Invalid number of arguments"});
		return 2;
	}
	var begin : usize = ft.fmt.parseInt(usize, args[1], 0) catch {
		utils.print_error("{s}", .{"Bad arguments"});
		return 2;
	};
	var len : usize = ft.fmt.parseInt(usize, args[2], 0) catch {
		utils.print_error("{s}", .{"Bad arguments"});
		return 2;
	};
	utils.memory_dump(begin, begin +| len);
	return 0;
}

pub fn mmap(_: [][]u8) usize {
	utils.print_mmap();
	return 0;
}

pub fn keymap(args: [][]u8) usize {
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
		2 => {
			km.set_keymap(args[1]) catch {
				utils.print_error("{s}", .{"Bad arguments"});
				return 2;
			};
		},
		else => {
			utils.print_error("{s}", .{"Invalid number of arguments"});
			return 2;
		}
	}
	return 0;
}