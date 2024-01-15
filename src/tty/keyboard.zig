const ft = @import("../ft/ft.zig");
const tty = @import("tty.zig");
const ports = @import("../drivers/ports.zig");
const keymap = @import("keyboard/keymap.zig");
const scanmap = @import("keyboard/scanmap.zig");
const scanmap_normal = scanmap.scanmap_normal;
const scanmap_special = scanmap.scanmap_special;

const SCANCODE_MASK_RELEASED =	0x80;
const SCANCODE_MASK_INDEX =		0x7F;
const KEYBOARD_INPUT_SIZE =		32;

var inbuf: [KEYBOARD_INPUT_SIZE]u16 = [_]u16{0} ** KEYBOARD_INPUT_SIZE;
var intail: u8 = 0;
var inhead: u8 = 0;
var incount: u8 = 0;

pub const KeyState = packed struct {
	shift_left: bool = false,
	shift_right: bool = false,
	shift: bool = false,
	ctrl_left: bool = false,
	ctrl_right: bool = false,
	ctrl: bool = false,
	alt_left: bool = false,
	alt_right: bool = false,
	alt: bool = false,
	num_down: bool = false,
	caps_down: bool = false,
	alt_lock: bool = false,
};

pub const KeyLocks = packed struct {
	caps_lock: bool = false,
	num_lock: bool = false,
};

const ScanMode = enum (u2) {
	Normal = 0,
	Extended = 1,
	Pause = 2,
};

pub var keyState: KeyState = .{};
var scan_mode: ScanMode = .Normal;
var locks: KeyLocks = .{};

pub fn send_to_tty(data: []const u8) void {
	const current: *tty.Tty = &tty.tty_array[tty.current_tty];

	current.input(data);
}

fn send_to_buffer(scan_code: u16) void {
	if (incount < KEYBOARD_INPUT_SIZE) {
		inbuf[inhead] = scan_code;
		inhead = (inhead + 1) % KEYBOARD_INPUT_SIZE;
		incount += 1;
	}
}

fn make_break(scancode: u16) ?u16 {
	var c = scancode & 0x7FFF;
	var make: bool = !(scancode & 0x8000 != 0);

	c = keymap.map_key(c, locks, keyState);
	switch (c) {
		keymap.RCTRL   => { keyState.ctrl_right  = make; keyState.ctrl  = make;  },
		keymap.LCTRL   => { keyState.ctrl_left   = make; keyState.ctrl  = make;  },
		keymap.RSHIFT  => { keyState.shift_right = make; keyState.shift = make;  },
		keymap.LSHIFT  => { keyState.shift_left  = make; keyState.shift = make;  },
		keymap.RALT    => { keyState.alt_right   = make; keyState.alt   = make;  },
		keymap.LALT    => { keyState.alt_left    = make; keyState.alt   = make;  },
		keymap.CALOCK  => {
			if (!keyState.caps_down and make)
				locks.caps_lock = !locks.caps_lock;
			keyState.caps_down = make;
		},
		keymap.NLOCK => {
			if (!keyState.num_down and make)
				locks.num_lock = !locks.num_lock;
			keyState.num_down = make;
		},
		else => if (make and c != 0)
				return c,
	}
	return null;
}

pub fn kb_read() void {
	if (incount == 0) return ;

	const scancode: u16 = inbuf[intail];

	intail = (intail + 1) % KEYBOARD_INPUT_SIZE;
	incount -|= 1;

	const c = make_break(scancode) orelse return;

	switch (c) {
		0...0xff => send_to_tty(&[1]u8 {@intCast(c)}),
		keymap.HOME...keymap.INSRT => send_to_tty(keymap.escape_map[c - keymap.HOME]),
		else => {},
	}
}

fn handler() void {
	const scan_code : u8 = ports.inb(ports.Ports.keyboard_data);
	const index : u8 = scan_code & SCANCODE_MASK_INDEX;
	const released : u16 = scan_code & SCANCODE_MASK_RELEASED;

	scan_mode = switch (scan_mode) {
		.Extended => b: {
			if (index < scanmap_special.len and scanmap_special[index] != .NONE)
				send_to_buffer(@intFromEnum(scanmap_special[index]) | (released << 8));
			break :b .Normal;
		},
		.Pause => .Normal, // Skip the byte, it's a pause and i personnaly don't care yet
		.Normal => switch (scan_code) {
			0xE0 => .Extended,
			0xE1 => .Pause,
			else => b: {
				if (index < scanmap_normal.len and scanmap_normal[index] != .NONE)
					send_to_buffer(@intFromEnum(scanmap_normal[index]) | (released << 8));
				break :b .Normal;
			}
		},
	};
}

fn is_key_available() bool {
	return ports.inb(ports.Ports.keyboard_status) & 1 == 1;
}

/// Is designed to crudely simulate the keyboard interrupt handler
pub fn simulate_keyboard_interrupt() void {
	if (is_key_available()) {
		handler();
	}
}
