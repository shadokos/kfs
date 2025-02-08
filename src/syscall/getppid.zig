pub const Id = 10;
const scheduler = @import("../task/scheduler.zig");
const task = @import("../task/task.zig");

pub fn do() !task.TaskDescriptor.Pid {
    return if (scheduler.get_current_task().parent) |parent| parent.pid else 0;
}
