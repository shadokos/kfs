pub const Id = 51;
const scheduler = @import("../task/scheduler.zig");
const task = @import("../task/task.zig");

// TODO
pub fn do(buf: [*]align(1) u8, len: usize) !void {
    if (len < 2) {
        return error.ENAMETOOLONG;
    }
    buf[0] = '/';
    buf[1] = 0;
}
