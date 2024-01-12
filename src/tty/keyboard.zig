const ft = @import("../ft/ft.zig");
const tty = @import("tty.zig");

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

pub fn send_to_tty() void {
	const current: *tty.Tty = &tty.tty_array[tty.current_tty];
	_ = current;
}
