const ports = @import("ports.zig");

var key_state: packed struct { shift: bool, ctrl: bool, alt: bool } = .{
	.shift = false,
	.ctrl = false,
	.alt = false,
};

pub fn is_key_available() bool {
	return ports.inb(ports.Ports.keyboard_status) & 1 == 1;
}

pub fn handler() void {
	const scan_code : u8 = ports.inb(ports.Ports.keyboard_data);
	const released : bool = scan_code & 0x80 != 0;

	if (scan_code == 0xe0) { // sequence keys
		_ = ports.inb(ports.Ports.keyboard_data);
	}
	switch (scan_code & 0x7f) {
		0x2a, 0x36 => { // ShiftL, ShiftR
			key_state.shift = !released;
			return;
		},
		// TODO: handle other keys
		else => {
		}
	}
}