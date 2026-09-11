pub const Id = 9;
const scheduler = @import("../task/scheduler.zig");
const task = @import("../task/task.zig");

pub fn do() !task.TaskDescriptor.Pid {
    return scheduler.get_current_task().pid;
}
