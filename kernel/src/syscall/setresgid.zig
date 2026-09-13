pub const Id = 65;
const scheduler = @import("../task/scheduler.zig");
const Task = @import("../task/task.zig").TaskDescriptor;

pub fn do(rgid : Task.Gid, egid : Task.Gid, sgid : Task.Gid) !void {
    const task = scheduler.get_current_task();
    const is_privileged = task.euid == 0;
    const can_set_sgid =  is_privileged or (sgid != task.gid and sgid != task.egid and sgid != task.sgid);
    const can_set_rgid =  is_privileged or (rgid != task.gid and rgid != task.egid and rgid != task.sgid);
    const can_set_egid = is_privileged or (egid != task.gid and egid != task.egid and egid != task.sgid);
    if ((rgid != -1 and !can_set_rgid) or (egid != -1 and !can_set_egid) or (sgid != -1 and !can_set_sgid)) {
        return error.EPERM;
    }
    if (rgid != -1) {
        task.gid = rgid;
    }
    if (egid != -1) {
        task.egid = egid;
    }
    if (sgid != -1) {
        task.sgid = sgid;
    }
}
