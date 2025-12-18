const std = @import("std");
pub const Id = 24;
const Errno = @import("../errno.zig").Errno;
const vfs = @import("../fs/vfs.zig");
const TNode = @import("../fs/tnode.zig");
const INode = @import("../fs/inode.zig");
const scheduler = @import("../task/scheduler.zig");
const TaskDescriptor = @import("../task/task.zig").TaskDescriptor;

const Mode = @import("open.zig").Mode;

pub fn do(fd: TaskDescriptor.Fd) !void {
    const file = scheduler.get_current_task().get_file(fd) orelse return error.EBADF;
    try file.close();
    scheduler.get_current_task().remove_file(fd);
}
