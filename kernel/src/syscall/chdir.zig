pub const Id = 52;
const std = @import("std");
const scheduler = @import("../task/scheduler.zig");
const task = @import("../task/task.zig");
const vfs = @import("../fs/vfs.zig");

pub fn do(path: [*:0]const u8) !void {
    const tnode = try vfs.resolve(std.mem.span(path));
    try scheduler.get_current_task().chdir(tnode);
}
