const mmio_console = @import("./mmio_console.zig");

fn init_console(c: *mmio_console.Buffer) void {
    c.init_writer();
    c.set_font_color(mmio_console.Color.white);
    c.set_view_bottom();
}

var console = mmio_console.Buffer{};

export fn kernel_main() void {
	init_console(&console);
    console.printf("hello, {}", .{42});
    console.view();
}
