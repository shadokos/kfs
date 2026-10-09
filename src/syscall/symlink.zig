const std = @import("std");
pub const Id = 23;
const Errno = @import("../errno.zig").Errno;
const vfs = @import("../fs/vfs.zig");
const TNode = @import("../fs/tnode.zig");
const INode = @import("../fs/inode.zig");
const scheduler = @import("../task/scheduler.zig");
const TaskDescriptor = @import("../task/task.zig").TaskDescriptor;

const Mode = @import("open.zig").Mode;

pub fn do(path1: [*:0]const u8, path2: [*:0]const u8) Errno!void {
    const path_slice = std.mem.span(path2);
    const dir_path = std.fs.path.dirnamePosix(path_slice) orelse if (std.fs.path.isAbsolutePosix(path_slice)) "/" else ".";
    const name = std.fs.path.basenamePosix(path_slice);

    const dir_tnode = try vfs.resolve(dir_path);
    defer dir_tnode.release();

    // todo: lock dir_tnode.inode to ensure atomicity

    if (dir_tnode.lookup(name)) |existing| {
        existing.release();
        return Errno.EEXIST;
    }

    const inode = try dir_tnode.inode.superblock.create_inode(
        0,
        0,
        .{
            .type = .Link,
        },
        .{ .Link = std.mem.span(path1) },
    );
    defer inode.release();

    try dir_tnode.inode.link(name, inode);
}
