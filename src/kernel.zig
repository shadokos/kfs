const tty = @import("./tty/tty.zig");
const keyboard = @import("./keyboard.zig");

fn init_console(c: *tty.Tty) void {
    c.init_writer();
    c.set_font_color(tty.Color.white);
    c.set_view_bottom();
}

var console = tty.Tty {};

export fn kernel_main() void {
	const console = &tty.tty_array[tty.current_tty];
    try console.writer().print("hello, \x1b[32m{d}\x1b[37m", .{42});
    console.view();

   	while (true) {
		if (keyboard.is_key_available()) keyboard.handler();
   	}
}
