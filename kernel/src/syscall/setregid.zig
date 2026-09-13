pub const Id = 63;
const scheduler = @import("../task/scheduler.zig");
const Task = @import("../task/task.zig").TaskDescriptor;

pub fn do(rgid : Task.Gid, egid : Task.Gid) !void {
    const task = scheduler.get_current_task();
    const is_privileged = task.euid == 0;
    const can_set_rgid =  is_privileged or (rgid != task.gid and rgid != task.egid);
    const can_set_egid = is_privileged or (egid != task.gid and egid != task.egid and egid != task.sgid);
    if ((rgid != -1 and !can_set_rgid) or (egid != -1 and !can_set_egid)) {
        return error.EPERM;
    }
    const old_gid = task.gid;
    if (rgid != -1) {
        task.gid = rgid;
    }
    if (egid != -1) {
        task.egid = egid;
    }
    if (rgid != -1 or egid != old_gid) {
    }
}
