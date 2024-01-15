const tty = @import("./tty/tty.zig");
const keyboard = @import("./tty/keyboard.zig");

export fn kernel_main() void {
	const console = &tty.tty_array[tty.current_tty];
    try console.writer().print("hello, \x1b[32m{d}\x1b[37m\n", .{42});
    console.view();
}
