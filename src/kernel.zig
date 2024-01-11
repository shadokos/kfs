const tty = @import("./tty/tty.zig");
const keyboard = @import("./keyboard.zig");

export fn kernel_main() void {
	const console = &tty.tty_array[tty.current_tty];
    try console.writer().print("hello, \x1b[32m{d}\x1b[37m", .{42});
    console.view();

   	while (true) {
		if (keyboard.is_key_available()) keyboard.handler();
   	}
}
