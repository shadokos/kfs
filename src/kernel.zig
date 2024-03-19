const tty = @import("./tty/tty.zig");
const DefaultShell = @import("shell/default/shell.zig");
const printk = tty.printk;

pub fn main() void {
    printk("hello, \x1b[32m{d}\x1b[0m\n", .{42});

    var shell = DefaultShell.Shell.init(tty.get_reader(), tty.get_writer(), .{}, .{
        .pre_process = DefaultShell.pre_process,
        .on_error = DefaultShell.on_error,
    });
    while (true) _ = shell.process_line();
}
