const keyboard = @import("./tty/keyboard.zig");
const printk = @import("./tty/tty.zig").printk;
const shell = @import("./shell.zig").shell;
const ps2 = @import("./drivers/ps2/ps2.zig");

pub fn main() void {
	ps2.init();
    printk("hello, \x1b[32m{d}\x1b[37m\n", .{42});
	_ = shell();
}
