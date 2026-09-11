pub const Id = 48;
const scheduler = @import("../task/scheduler.zig");

pub fn do() !u32 {
    return scheduler.get_current_task().gid;
}
