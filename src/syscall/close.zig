const std = @import("std");
pub const Id = 24;
const Errno = @import("../errno.zig").Errno;
const vfs = @import("../fs/vfs.zig");
const TNode = @import("../fs/tnode.zig");
const INode = @import("../fs/inode.zig");
const scheduler = @import("../task/scheduler.zig");
const TaskDescriptor = @import("../task/task.zig").TaskDescriptor;
const FileSet = @import("../task/file_set.zig");

const Mode = @import("open.zig").Mode;

pub fn do(fd: FileSet.Fd) !void {
    try scheduler.get_current_task().files.remove(fd);
}
