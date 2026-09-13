pub const Id = 62;
const scheduler = @import("../task/scheduler.zig");
const Task = @import("../task/task.zig").TaskDescriptor;

pub fn do(ruid : Task.Uid, euid : Task.Uid) !void {
    const task = scheduler.get_current_task();
    const is_privileged = task.euid == 0;
    const can_set_ruid =  is_privileged or (ruid != task.uid and ruid != task.euid);
    const can_set_euid = is_privileged or (euid != task.uid and euid != task.euid and euid != task.suid);
    if ((ruid != -1 and !can_set_ruid) or (euid != -1 and !can_set_euid)) {
        return error.EPERM;
    }
    const old_uid = task.uid;
    if (ruid != -1) {
        task.uid = ruid;
    }
    if (euid != -1) {
        task.euid = euid;
    }
    if (ruid != -1 or euid != old_uid) {
    }
}
