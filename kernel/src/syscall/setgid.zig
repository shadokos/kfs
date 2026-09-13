pub const Id = 66;
const scheduler = @import("../task/scheduler.zig");
const Task = @import("../task/task.zig").TaskDescriptor;

pub fn do(gid : Task.Gid) !void {
    const task = scheduler.get_current_task();
    if (task.euid == 0) {
        task.gid = gid;
        task.egid = gid;
        task.sgid = gid;
    } else if (gid == task.gid or gid == task.sgid) {
        task.egid = gid;
    } else return error.EPERM;
}
