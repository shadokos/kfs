pub const Id = 15;
const scheduler = @import("../task/scheduler.zig");
const Task = @import("../task/task.zig").TaskDescriptor;

pub fn do(ruid : *Task.Uid, euid : *Task.Uid, suid : *Task.Uid) !void {
    const task = scheduler.get_current_task();
    ruid.* = task.uid;
    euid.* = task.euid;
    suid.* = task.suid;
}
