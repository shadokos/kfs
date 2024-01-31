const tty = @import("../tty/tty.zig");
const ft = @import("../ft/ft.zig");
const StackIterator = ft.debug.StackIterator;

extern var STACK_SIZE: usize;
extern var stack: u8;

pub const inverse = "\x1b[7m";
pub const red = "\x1b[31m";
pub const green = "\x1b[32m";
pub const yellow = "\x1b[33m";
pub const blue = "\x1b[34m";
pub const magenta = "\x1b[35m";
pub const cyan = "\x1b[36m";
pub const white = "\x1b[37m";
pub const bg_red = "\x1b[41m";
pub const bg_green = "\x1b[42m";
pub const bg_yellow = "\x1b[43m";
pub const bg_blue = "\x1b[44m";
pub const bg_magenta = "\x1b[45m";
pub const bg_cyan = "\x1b[46m";
pub const bg_white = "\x1b[47m";
pub const reset = "\x1b[0m";

const prompt: *const [2:0]u8 = "$>";

pub fn ensure_newline() void {
	tty.printk("{s}\x1b[{d}C\r", .{
		inverse ++ "%" ++ reset, // No newline char: '%' character in reverse
		tty.width - 2, // Move cursor to the end of the line or on the next line if the line is not empty
	});
}

pub fn print_error(msg: []const u8) void {
	ensure_newline();
	tty.printk(red ++ "Error:" ++ reset ++ " {s}\n", .{msg});
}

pub fn print_prompt(status_code: usize) void {
	ensure_newline();
	tty.printk("{s}{s}" ++ reset ++ " ", .{ // print the prompt:
		if (status_code != 0) red else cyan, // prompt collor depending on the last command status
		prompt, // prompt
	});
}

pub fn memory_dump(start_address: usize, end_address: usize) void {
    var start = @min(start_address, end_address);
    var end = @max(start_address, end_address);

    var i: usize = 0;
    while (start + i < end) : ({ i += 16; }) {
        var ptr: usize = start + i;
        var offset: usize = 0;
        var offsetPreview: usize = 0;
        var line: [67]u8 = [_]u8{' '} ** 67;

        _ = ft.fmt.bufPrint(&line, "{x:0>8}: ", .{start + i}) catch {};

        while (ptr + 1 < start + i + 16 and ptr < end) : ({
            ptr += 2;
            offset += 5;
            offsetPreview += 2;
        }) {
            var byte1: u8 = @as(*u8, @ptrFromInt(ptr)).*;
            var byte2: u8 = @as(*u8, @ptrFromInt(ptr + 1)).*;

            _ = ft.fmt.bufPrint(line[10 + offset..], "{x:0>2}{x:0>2} ", .{byte1, byte2}) catch {};
            _ = ft.fmt.bufPrint(line[51 + offsetPreview..], "{s}{s}", .{
                [_]u8{if (ft.ascii.isPrint(byte1)) byte1 else '.'},
                [_]u8{if (ft.ascii.isPrint(byte2)) byte2 else '.'},
            }) catch {};
        }

        tty.printk("{s}\n", .{line});
    }
}

pub fn print_stack() void {
	var si: StackIterator = StackIterator.init(null, @frameAddress());
	var esp: usize = 0;
	var old_fp: usize = 0;
	var link: bool = false;

	asm volatile("movl %esp, %[esp]" : [esp] "=r" (esp));

	tty.printk("{s}EBP{s}, {s}ESP{s}, {s}PC{s}, {s}Size{s}\n", .{
		yellow, reset,
		red, reset,
		blue, reset,
		green, reset
	});
	tty.printk("   \xDA" ++ "\xC4" ** 12 ++ "\xBF <- {s}0x{x:0>8}{s}\n", .{
		red, esp, reset
	});
	while (true) {
		const size = si.fp - esp;

		tty.printk("{s}\xB3 {s}0x{x:0>8}{s} \xB3\n", .{
			if (link) "\xB3  " else "   ", green, size, reset
		});
		tty.printk("{s}\xC3" ++ "\xC4"**12 ++ "\xB4\n", .{
			if (link) "\xB3  " else "   ", "\x1b[C"**3
		});
		old_fp = si.fp;
		esp = si.fp - @sizeOf(usize);
		if (si.next()) |addr| {
			tty.printk("{s}\xB3 {s}0x{x:0>8}{s} \xB3 <- {s}0x{x:0>8}{s}\n", .{
				if (link) "\xC0> " else "   ",
				yellow, si.fp, reset, yellow, old_fp, reset,
			});
			link = true;
			tty.printk("   \xC0\xC4\xC2" ++ "\xC4"**10 ++ "\xD9\n", .{});
			tty.printk("\xDA" ++ "\xC4"**4 ++ "\xD9\n", .{});
			tty.printk("\xB3  \xDA" ++ "\xC4"**12 ++ "\xBF\n", .{});
			tty.printk("\xB3  \xB3 {s}0x{x:0>8}{s} \xB3 <- {s}0x{x:0>8}{s}\n", .{
				blue, addr, reset,
				red, esp, reset,
			});
			tty.printk("\xB3  \xC3" ++ "\xC4" ** 12 ++ "\xB4\n", .{});
		} else {
			tty.printk("{s}\xB3 {s}0x{x:0>8}{s} \xB3 <- {s}0x{x:0>8}{s}\n", .{
        		if (link) "\xC0> " else "   ",
        		yellow, @as(*const usize, @ptrFromInt(si.fp)).*, reset, yellow, si.fp, reset,
        	});
			tty.printk("   \xC0" ++ "\xC4"**12 ++ "\xD9\n", .{});
			break;
		}
	}
}
