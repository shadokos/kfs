pub const Id = 15;
const scheduler = @import("../task/scheduler.zig");

pub fn do() !u32 {
    return scheduler.get_current_task().owner;
}
