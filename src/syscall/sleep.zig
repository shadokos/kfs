pub const Id = 1;

pub fn do(ms: u32) !void {
    try @import("../task/sleep.zig").sleep(ms);
}
