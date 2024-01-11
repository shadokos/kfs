const ports = @import("ports.zig");
const scanmap_normal = @import("scanmap.zig").scanmap_normal;
const scanmap_special = @import("scanmap.zig").scanmap_special;
const InputKey = @import("scanmap.zig").InputKey;

const SCANCODE_MASK_RELEASED =	0x80;
const SCANCODE_MASK_INDEX =		0x7F;
const KEYBOARD_INPUT_SIZE =		32;

var inbuf: [KEYBOARD_INPUT_SIZE]u16 = [_]u16{0} ** KEYBOARD_INPUT_SIZE;
var intail: u8 = 0;
var inhead: u8 = 0;
var incount: u8 = 0;

fn send_to_buffer(scan_code: u16) void {
	if (incount < KEYBOARD_INPUT_SIZE) {
		inbuf[inhead] = scan_code;
		inhead = (inhead + 1) % KEYBOARD_INPUT_SIZE;
		incount += 1;
	}
}

pub fn count_buffer() u8 {
	return incount;
}

pub fn read_buffer() ?u16 {
	if (incount == 0) return null;

	const scancode: u16 = inbuf[intail];
	intail = (intail + 1) % KEYBOARD_INPUT_SIZE;
	incount -|= 1;

	return scancode;
}

var kbstate : u8 = 0;

fn handler() void {
	const scan_code : u8 = ports.inb(ports.Ports.keyboard_data);
	const index : u8 = scan_code & SCANCODE_MASK_INDEX;
	const released : u16 = scan_code & SCANCODE_MASK_RELEASED;
	var code : InputKey = InputKey.NONE;

	switch (kbstate) {
		1 => if (index < scanmap_special.len) {
			code = scanmap_special[index];
		},
		2 => { return ; }, // Skip the byte, it's a pause and i personnaly don't care yet
		else => {
			switch (scan_code) {
				0xE0 => { kbstate = 1; return ;	},
				0xE1 => { kbstate = 2; return ;	},
				else => if (index < scanmap_normal.len) {
					code = scanmap_normal[index];
				}
			}
		},
	}
	kbstate = 0;

	if (code != InputKey.NONE) {
		send_to_buffer(@intFromEnum(code) | (released << 8));
	}
}

fn is_key_available() bool {
	return ports.inb(ports.Ports.keyboard_status) & 1 == 1;
}

// Is designed to crudely simulate the keyboard interrupt handler
pub fn simulate_keyboard_interrupt() void {
	if (is_key_available()) {
		handler();
	}
}

// Print the keyboard buffer
pub fn debug_buffer(console: *@import("./tty/tty.zig").Tty) void {
	var i: u8 = 0;
	const bytes_per_line: u8 = 2;
	while (i < KEYBOARD_INPUT_SIZE) : (i += bytes_per_line) {
		for (i..i+bytes_per_line) |j| {
			if (j == inhead and j == intail) { console.putstr("\x1b[33m"); }
			else if (j == inhead) { console.putstr("\x1b[31m"); }
			else if (j == intail) { console.putstr("\x1b[32m"); }
			console.printf("{b:0>16}\x1b[30m (x{x:0>4})\x1b[37m ", .{
				inbuf[j],
				inbuf[j],
			});
		}
		console.putchar('\n');
	}
	console.putstr("\n" ** (25 - (32 / bytes_per_line) - 1));
	console.view();
}
