pub const Id = 3;
const scheduler = @import("../task/scheduler.zig");
const signal = @import("../task/signal.zig");
const task = @import("../task/task.zig");
const task_set = @import("../task/task_set.zig");
const Errno = @import("../errno.zig").Errno;

// todo: invalid id
pub fn do(pid: task.TaskDescriptor.Pid, id: signal.Id) !void {
    if (pid > 0) {
        const descriptor = task_set.get_task_descriptor(pid) orelse return Errno.ESRCH;
        // todo permisssion
        var info = signal.siginfo_t.init(.{ .user = id });
        info.si_pid = scheduler.get_current_task().pid;
        // todo set more fields of siginfo
        descriptor.send_signal(info);
    } else if (pid == 0) {
        const pgid = scheduler.get_current_task().pgid;
        var info = signal.siginfo_t.init(.{ .user = id });
        info.si_pid = scheduler.get_current_task().pid;
        if (task_set.send_signal_to_group(pgid, info) == 0) return Errno.ESRCH;
    } else if (pid == -1) {
        // todo: every process for which the calling process has  per-
        // mission to send signals, except for process 1
    } else { // pid < -1
        var info = signal.siginfo_t.init(.{ .user = id });
        info.si_pid = scheduler.get_current_task().pid;
        if (task_set.send_signal_to_group(-pid, info) == 0) return Errno.ESRCH;
    }
}
