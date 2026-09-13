pub const Id = 47;
const scheduler = @import("../task/scheduler.zig");
const Task = @import("../task/task.zig").TaskDescriptor;

pub fn do(rgid : *Task.Gid, egid : *Task.Gid, sgid : *Task.Gid) !void {
    const task = scheduler.get_current_task();
    rgid.* = task.gid;
    egid.* = task.egid;
    sgid.* = task.sgid;
}
