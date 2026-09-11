const scheduler = @import("../task/scheduler.zig");
const task_set = @import("../task/task_set.zig");
const TaskDescriptor = @import("../task/task.zig").TaskDescriptor;

pub const Id = 39;

/// The session a task belongs to, POSIX getsid. Zero means the caller.
pub fn do(pid: TaskDescriptor.Pid) !TaskDescriptor.Pid {
    const task = if (pid == 0)
        scheduler.get_current_task()
    else
        task_set.get_task_descriptor(pid) orelse return error.ESRCH;

    return task.session.sid;
}
