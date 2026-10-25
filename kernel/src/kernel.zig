const DefaultShell = @import("shell/default/shell.zig");
const tty = @import("./tty/tty.zig");

pub fn main(_: usize) u8 {
    var shell = DefaultShell.Shell.init(tty.get_reader(), tty.get_writer(), .{}, .{
        .on_init = DefaultShell.on_init,
        .pre_prompt = DefaultShell.pre_process,
    });
    while (true) shell.process_line();
}
