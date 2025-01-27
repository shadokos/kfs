const exit = @import("../task/task.zig").exit;

pub const Id = 6;

pub fn do(code: u8) !void {
    exit(code);
}
