const tty = @import("./tty/tty.zig");

fn init_console(c: *tty.Tty) void {
    c.init_writer();
    c.set_font_color(tty.Color.white);
    c.set_view_bottom();
}

var console = tty.Tty {};

export fn kernel_main() void {
	init_console(&console);
    console.printf("hello, \x1b[32m{d}\x1b[38m", .{42});
    console.view();
}
