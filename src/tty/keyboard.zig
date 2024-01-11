const ft = @import("../ft/ft.zig");
const tty = @import("tty.zig");

pub fn send_to_tty() void {
	const current: *tty.Tty = &tty.tty_array[tty.current_tty];
	_ = current;
}
