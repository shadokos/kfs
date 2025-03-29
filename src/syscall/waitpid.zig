const scheduler = @import("../task/scheduler.zig");
const task = @import("../task/task.zig");
const Pid = task.TaskDescriptor.Pid;
const wait = @import("../task/wait.zig");

pub const Id = 17;

pub fn do(pid: Pid, stat_loc: ?*wait.Status, options: wait.WaitOptions) !Pid {
    if (pid == -1) {
        return wait.wait(scheduler.get_current_task().pid, .CHILD, stat_loc, null, options);
    } else if (pid > 0) {
        return wait.wait(pid, .SELF, stat_loc, null, options);
    } else if (pid == 0) {
        @panic("todo Process groups not implemented");
    } else {
        @panic("todo Process groups not implemented");
    }
}
