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

var kbstate : u8 = 0;

var locks: u16 = 0;

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

pub var keyState: KeyState = .{};

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

	c = keymap.map_key(c, locks, &keyState);
	switch (c) {
		keymap.RCTRL   => { keyState.ctrl_right  = make; keyState.ctrl  = make;  },
		keymap.LCTRL   => { keyState.ctrl_left   = make; keyState.ctrl  = make;  },
		keymap.RSHIFT  => { keyState.shift_right = make; keyState.shift = make;  },
		keymap.LSHIFT  => { keyState.shift_left  = make; keyState.shift = make;  },
		keymap.RALT    => { keyState.alt_right   = make; keyState.alt   = make;  },
		keymap.LALT    => { keyState.alt_left    = make; keyState.alt   = make;  },
		keymap.CALOCK  => {
			if (!keyState.caps_down and make) locks ^= keymap.CAPS_LOCK;
			keyState.caps_down = make;
		},
		keymap.NLOCK => {
			if (!keyState.num_down and make) locks ^= keymap.NUM_LOCK;
			keyState.num_down = make;
		},
		else => {
			if (!make) return null;
			if (c != 0) return c;
			return null;
		}
	}
	return null;
}

pub fn kb_read() void {
	if (incount == 0) return ;

	const scancode: u16 = inbuf[intail];
	const index: u16 = scancode & 0x7FFF;

	intail = (intail + 1) % KEYBOARD_INPUT_SIZE;
	incount -|= 1;

	_ = index;
	const c = make_break(scancode) orelse return;

	switch (c) {
		0...0xff =>  {
		 	send_to_tty(&[1]u8 {@as(u8, @intCast(c))});
		},
		keymap.HOME...keymap.INSRT => {
			if (c == keymap.PGUP) { send_to_tty("\x1bD"); }
			else if (c == keymap.PGDN) { send_to_tty("\x1bM"); }
			else { send_to_tty("\x1b[" ++ [_]u8 {keymap.escape_map[c - keymap.HOME]}); }
		},
		else => {},
	}
}

fn handler() void {
	const scan_code : u8 = ports.inb(ports.Ports.keyboard_data);
	const index : u8 = scan_code & SCANCODE_MASK_INDEX;
	const released : u16 = scan_code & SCANCODE_MASK_RELEASED;
	var code : scanmap.InputKey = .NONE;

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

	if (code != .NONE) {
		send_to_buffer(@intFromEnum(code) | (released << 8));
	}
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
