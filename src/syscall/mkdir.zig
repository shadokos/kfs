const std = @import("std");
pub const Id = 22;
const Errno = @import("../errno.zig").Errno;
const vfs = @import("../fs/vfs.zig");
const TNode = @import("../fs/tnode.zig");
const INode = @import("../fs/inode.zig");
const scheduler = @import("../task/scheduler.zig");
const TaskDescriptor = @import("../task/task.zig").TaskDescriptor;

const Mode = @import("open.zig").Mode;

pub fn do(path: [*:0]const u8, mode: Mode) Errno!void {
    const path_slice = std.mem.span(path);
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
        mode.to_vfs(.Directory),
        .{ .Directory = .{ .parent_ino = dir_tnode.inode } },
    );
    defer inode.release();

    try dir_tnode.inode.link(name, inode);
}
