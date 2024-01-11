const tty = @import("./tty/tty.zig");
const keyboard = @import("./keyboard.zig");

export fn kernel_main() void {
	const console = &tty.tty_array[tty.current_tty];
    try console.writer().print("hello, \x1b[32m{d}\x1b[37m", .{42});
    console.view();

   	while (true) {
   		keyboard.simulate_keyboard_interrupt();
   		if (keyboard.read_buffer()) |input| {
   			console.printf("key: {d:>5} 0b{b:0>16} 0x{x:0>4} {}\n", .{
   				input,
   				input,
   				input,
   				@as(@import("scanmap.zig").InputKey, @enumFromInt(input & 0x7fff)),
   			});
   		}
   		console.view();
   	}
}
