pub const Id = 60;
const scheduler = @import("../task/scheduler.zig");
const Task = @import("../task/task.zig").TaskDescriptor;

pub fn do(uid : Task.Uid) !void {
    const task = scheduler.get_current_task();
    if (task.euid == 0 or uid == task.uid or uid == task.suid) {
        task.euid = uid;
    } else return error.EPERM;
}
