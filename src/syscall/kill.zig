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
        descriptor.send_signal(.{
            .si_signo = .{ .valid = id },
            .si_code = .SI_USER,
            .si_pid = scheduler.get_current_task().pid,
            // todo set more fields of siginfo
        });
    } else if (pid == 0) {
        // todo: process group
    } else if (pid == -1) {
        // todo: every process for which the calling process has  per-
        // mission to send signals, except for process 1
    } else { // pid < -1
        // todo: process group with id -id
    }
}
