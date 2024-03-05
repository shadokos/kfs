const ft = @import("../ft/ft.zig");
const tty = @import("../tty/tty.zig");
const helpers = @import("helpers.zig");
const utils = @import("utils.zig");
const CmdError = @import("../shell.zig").CmdError;
const printk = tty.printk;

pub fn stack(_: anytype) CmdError!void {
	if (@import("build_options").optimize != .Debug) {
		utils.print_error("{s}", .{"The stack builtin is only available in debug mode"});
		return CmdError.OtherError;
	}
	utils.dump_stack();
	utils.print_stack();
}

fn _help_available_commands() void {
	printk(utils.blue ++ "Available commands:\n" ++ utils.reset, .{});
	inline for (@typeInfo(@This()).Struct.decls) |decl| {
		printk("  - {s}\n", .{decl.name});
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
	printk("\x1b[2J\x1b[H", .{});
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

pub fn elf(_: [][]u8) CmdError!void {
	utils.print_elf();
}

pub fn keymap(args: [][]u8) CmdError!void {
	const km = @import("../tty/keyboard/keymap.zig");
	switch(args.len) {
		1 => {
			const list = km.keymap_list;
			printk("Installed keymaps:\n\n", .{});
			for (list) |e| {
				printk(" - {s}\n", .{e});
			}
			printk("\n", .{});
		},
		2 => km.set_keymap(args[1]) catch return CmdError.InvalidParameter,
		else => return CmdError.InvalidNumberOfArguments
	}
}

pub fn theme(args: [][]u8) CmdError!void {
	const t = @import("../tty/themes.zig");
	switch(args.len) {
		1 => {
			const list = t.theme_list;
			printk("Available themes:\n\n", .{});
			for (list) |e| {
				printk(" - {s}\n", .{e});
			}
			printk("\n", .{});
			printk("Current palette:\n", .{});
			utils.show_palette();
		},
		2 => {
			tty.get_tty().set_theme(t.get_theme(args[1]) orelse return CmdError.InvalidParameter);
			printk("\x1b[2J\x1b[H", .{});
			utils.show_palette();
		},
		else => return CmdError.InvalidNumberOfArguments
	}
}

pub fn shutdown(_: [][]u8) CmdError!void {
	@import("../drivers/acpi/acpi.zig").power_off();
	utils.print_error("Failed to shutdown", .{});
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

pub fn vm(_: [][]u8) CmdError!void {
	@import("../memory.zig").virtualPageAllocator.print();
}

pub fn pm(_: [][]u8) CmdError!void {
	@import("../memory.zig").pageFrameAllocator.print();
}

const vpa = &@import("../memory.zig").virtualPageAllocator;

pub fn alloc_page(args: [][]u8) CmdError!void {
	if (args.len != 2) return CmdError.InvalidNumberOfArguments;
	const nb = ft.fmt.parseInt(usize, args[1], 0) catch return CmdError.InvalidParameter;
	const pages  = vpa.alloc_pages(nb) catch {
		printk("Failed to allocate {d} pages\n", .{nb});
		return CmdError.OtherError;
	};
	printk("Allocated {d} pages at 0x{x:0>8}\n", .{nb, @intFromPtr(pages)});
}

pub fn kmalloc(args: [][]u8) CmdError!void {
	if (args.len != 2) return CmdError.InvalidNumberOfArguments;
	var kmem = @import("../memory.zig").kernelMemoryAllocator;
	const nb = ft.fmt.parseInt(usize, args[1], 0) catch return CmdError.InvalidParameter;
	const obj : []u8 = kmem.alloc(u8, nb) catch {
		printk("Failed to allocate {d} bytes\n", .{nb});
		return CmdError.OtherError;
	};
	printk("Allocated {d} bytes at 0x{x}\n", .{nb, @intFromPtr(&obj[0])});
}

pub fn kfree(args: [][]u8) CmdError!void {
	if (args.len != 2) return CmdError.InvalidNumberOfArguments;

	var kmem = @import("../memory.zig").kernelMemoryAllocator;
	const addr = ft.fmt.parseInt(usize, args[1], 0) catch return CmdError.InvalidParameter;
	if (!ft.mem.isAligned(addr, @sizeOf(usize))) return CmdError.OtherError;
	//kmem.free(@ptrFromInt(addr));
	kmem.free(@as(*usize, @ptrFromInt(addr)));
}

pub fn ksize(args: [][]u8) CmdError!void {
	if (args.len != 2) return CmdError.InvalidNumberOfArguments;

	var kmem = @import("../memory.zig").kernelMemoryAllocator;
	const addr = ft.fmt.parseInt(usize, args[1], 0) catch return CmdError.InvalidParameter;
	if (!ft.mem.isAligned(addr, @sizeOf(usize))) return CmdError.OtherError;
	const size = kmem.obj_size(@as(*usize, @ptrFromInt(addr)));
	if (size) |s| printk("Size of 0x{x} is {d} bytes\n", .{addr, s})
	else printk("0x{x} is not a valid address\n", .{addr});
}

pub fn slabinfo(_: [][]u8) CmdError!void {
	const slab = @import("../memory/slab.zig");
	slab.slabinfo();
}

pub fn multiboot_info(_: [][]u8) CmdError!void {
	printk("{*}\n", .{@import("../boot.zig").multiboot_info});
	@import("../multiboot.zig").list_tags();
}

// TODO: Remove this builtin
// ... For debugging purposes only
pub fn cache_create(args: [][]u8) CmdError!void {
	if (args.len != 4) return CmdError.InvalidNumberOfArguments;
	const slab = @import("../memory/slab.zig");
	const name = args[1];
	const size = ft.fmt.parseInt(usize, args[2], 0) catch return CmdError.InvalidParameter;
	const order = ft.fmt.parseInt(usize, args[3], 0) catch return CmdError.InvalidParameter;
	const new_cache = slab.Cache.create(name, size, @truncate(order)) catch {
		printk("Failed to create cache\n", .{});
		return CmdError.OtherError;
	};
	printk("cache allocated: {*}\n", .{new_cache});
}

// TODO: Remove this builtin
// ... For debugging purposes only
pub fn cache_destroy(args: [][]u8) CmdError!void {
	if (args.len != 2) return CmdError.InvalidNumberOfArguments;

	const slab = @import("../memory/slab.zig");
	const addr = ft.fmt.parseInt(usize, args[1], 0) catch return CmdError.InvalidParameter;

	slab.Cache.destroy(@ptrFromInt(addr));
}

// TODO: Remove this builtin
// ... For debugging purposes only
pub fn shrink(_: [][]u8) CmdError!void {
	var node: ?*@import("../memory/slab.zig").Cache = &@import("../memory/slab.zig").global_cache;
	while (node) |n| : (node = n.next) n.shrink();
}

const KernelMemoryAllocator = @import("../memory/kernel_memory_allocator.zig").KernelMemoryAllocator;
const Fuzzer = @import("../memory/fuzzer.zig").Fuzzer(KernelMemoryAllocator);
var fuzzer : ?Fuzzer = null;
var allocator : KernelMemoryAllocator = .{};
pub fn fuzz(args: [][]u8) CmdError!void {
	if (args.len != 2) return CmdError.InvalidNumberOfArguments;
	const nb = ft.fmt.parseInt(usize, args[1], 0) catch return CmdError.InvalidParameter;

	if (fuzzer) |*f| {
		f.fuzz(nb) catch |e| {
			printk("error: {s}\n", .{@errorName(e)});
			f.status();
		};
	} else {
		fuzzer = Fuzzer.init(&allocator);
		return fuzz(args);
	}
}