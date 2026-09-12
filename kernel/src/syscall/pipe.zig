const std = @import("std");
pub const Id = 53;
const Errno = @import("../errno.zig").Errno;
const scheduler = @import("../task/scheduler.zig");
const TaskDescriptor = @import("../task/task.zig").TaskDescriptor;
const FileSet = @import("../task/file_set.zig");
const vfs = @import("../fs/vfs.zig");

pub fn do(pair: *[2]FileSet.Fd) !void {
    const task = scheduler.get_current_task();
    // todo: uid, gid
    const inode = try task.cwd.inode.superblock.create_inode(@intCast(task.uid), @intCast(task.gid), .{
        .type = .Fifo,
        .owner = .{
            .read = true,
            .write = true,
        },
    }, .{
        .Fifo = {},
    },);
    defer inode.release();
    pair[0] = try task.files.add(try inode.open(), 0);
    errdefer task.files.remove(pair[0]) catch @panic("todo");
    pair[1] = try task.files.add(try inode.open(), 0);
}
