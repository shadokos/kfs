const std = @import("std");
pub const Id = 25;
const Errno = @import("../errno.zig").Errno;
const vfs = @import("../fs/vfs.zig");
const TNode = @import("../fs/tnode.zig");
const INode = @import("../fs/inode.zig");
const scheduler = @import("../task/scheduler.zig");
const TaskDescriptor = @import("../task/task.zig").TaskDescriptor;

pub fn do(path: [*:0]const u8, _: [*:null]const ?[*:0]const u8, _: [*:null]const ?[*:0]const u8) Errno!void {
    const tnode = try vfs.resolve(std.mem.span(path));
    defer tnode.release();

    try scheduler.get_current_task().exec(tnode.inode, &.{}, &.{});
}
