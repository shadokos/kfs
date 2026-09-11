const scheduler = @import("../task/scheduler.zig");
const task_set = @import("../task/task_set.zig");
const TaskDescriptor = @import("../task/task.zig").TaskDescriptor;

pub const Id = 40;

/// Put a task in a process group, POSIX setpgid. Zero means the caller for
/// `pid`, and the task's own pid for `pgid`.
///
/// Only the caller or one of its children, within the caller's session, and
/// never a session leader.
pub fn do(pid: TaskDescriptor.Pid, pgid: TaskDescriptor.Pid) !void {
    const caller = scheduler.get_current_task();

    const task = if (pid == 0)
        caller
    else
        task_set.get_task_descriptor(pid) orelse return error.ESRCH;

    if (task != caller and task.parent != caller) return error.ESRCH;
    if (task.session.sid == task.pid) return error.EPERM;
    if (task.session != caller.session) return error.EPERM;

    const target = if (pgid == 0) task.pid else pgid;
    if (target < 0) return error.EINVAL;

    // Joining an existing group means joining it inside this session.
    if (target != task.pid) {
        const leader = task_set.get_task_descriptor(target) orelse return error.EPERM;
        if (leader.session != task.session) return error.EPERM;
    }

    task.pgid = target;
}
