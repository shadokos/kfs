const DefaultShell = @import("shell/default/shell.zig");
const tty = @import("./tty/tty.zig");

const task = @import("task/task.zig");
const wait = @import("task/wait.zig");
const task_set = @import("task/task_set.zig");
const scheduler = @import("task/scheduler.zig");

fn test_tasks() void {
    const new_task = task_set.create_task() catch @panic("Failed to create new_task");
    new_task.spawn(
        &@import("task/userspace.zig").switch_to_userspace,
        undefined,
    ) catch @panic("Failed to spawn new_task");
}

pub fn main(_: usize) u8 {
    test_tasks();

    var shell = DefaultShell.Shell.init(tty.get_reader(), tty.get_writer(), .{}, .{
        .on_init = DefaultShell.on_init,
        .pre_prompt = DefaultShell.pre_process,
    });
    while (true) shell.process_line();
}
