const DefaultShell = @import("shell/default/shell.zig");
const tty = @import("./tty/tty.zig");

pub fn main(_: usize) u8 {
    // Start ACPI event worker (must be done from task context, after scheduler init)
    @import("drivers/acpi/acpi.zig").start_event_worker();

    var shell = DefaultShell.Shell.init(tty.get_reader(), tty.get_writer(), .{}, .{
        .on_init = DefaultShell.on_init,
        .pre_prompt = DefaultShell.pre_process,
    });
    while (true) shell.process_line();
}
