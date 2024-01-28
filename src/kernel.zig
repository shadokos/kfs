const keyboard = @import("./tty/keyboard.zig");
const printk = @import("./tty/tty.zig").printk;
const shell = @import("./shell.zig").shell;

pub fn kernel_main() void {
    printk("hello, \x1b[32m{d}\x1b[37m\n", .{42});
	_ = shell();
}
