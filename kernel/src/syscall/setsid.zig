const scheduler = @import("../task/scheduler.zig");
const TaskDescriptor = @import("../task/task.zig").TaskDescriptor;
const Session = @import("../task/session.zig");

pub const Id = 38;

/// Start a session, POSIX setsid.
///
/// The caller becomes session leader and sole member of a new process group,
/// with no controlling terminal. A process group leader is refused, or its
/// group would end up split across two sessions.
pub fn do() !TaskDescriptor.Pid {
    const task = scheduler.get_current_task();
    if (task.pid == task.pgid) return error.EPERM;

    // Before letting the old one go: failing here must leave the task as it was.
    const session = try Session.create(task.pid);

    task.session.release();
    task.session = session;
    task.pgid = task.pid;
    return task.pid;
}
