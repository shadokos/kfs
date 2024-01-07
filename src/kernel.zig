const mmio_console = @import("./mmio_console.zig");

fn init_console(c: *mmio_console.BufferN(100)) void {
    c.init_writer();
    c.set_font_color(mmio_console.Color.white);
    c.set_view_bottom();
}

var console = mmio_console.BufferN(100){};

export fn kernel_main() void {
	init_console(&console);
    console.printf("hello, \x1b[32m{}\x1b[38m", .{42});
    console.view();
}
