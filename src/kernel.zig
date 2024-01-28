const keyboard = @import("./tty/keyboard.zig");
const printk = @import("./tty/tty.zig").printk;
const tty = @import("./tty/tty.zig");
const ft = @import("ft/ft.zig");

export fn kernel_main() void {
	tty.tty_array[tty.current_tty].config.c_lflag.ECHOCTL = true;
    printk("hello, \x1b[32m{d}\x1b[37m\n\x1b6n\x1b6n", .{42});
    while (true) {
    	var buf: [10]u8 = undefined;
    	var len = tty.get_reader().read(&buf) catch {};
    	printk("|{s}|", .{buf[0..len]});
    }
}
