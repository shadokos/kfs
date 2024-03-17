const tty = @import("./tty/tty.zig");
const Shell = @import("./shell.zig").Shell(@import("shell/builtins.zig"));
const printk = tty.printk;

pub fn main() void {
    printk("hello, \x1b[32m{d}\x1b[0m\n", .{42});

    var shell = Shell.init(tty.get_reader(), tty.get_writer());
    while (true) _ = shell.routine();
}
