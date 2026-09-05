const scheduler = @import("../task/scheduler.zig");
const task_set = @import("../task/task_set.zig");
const TaskDescriptor = @import("../task/task.zig").TaskDescriptor;

pub const Id = 41;

/// The process group of a task, POSIX getpgid. Zero means the caller.
pub fn do(pid: TaskDescriptor.Pid) !TaskDescriptor.Pid {
    const task = if (pid == 0)
        scheduler.get_current_task()
    else
        task_set.get_task_descriptor(pid) orelse return error.ESRCH;

    return task.pgid;
}
