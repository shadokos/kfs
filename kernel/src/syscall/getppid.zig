pub const Id = 50;
const scheduler = @import("../task/scheduler.zig");
const task = @import("../task/task.zig");

pub fn do() task.TaskDescriptor.Pid {
    if (scheduler.get_current_task().parent) |parent| {
        return parent.pid;
    } else {
        return 0; // todo: should we panic?
    }
}
