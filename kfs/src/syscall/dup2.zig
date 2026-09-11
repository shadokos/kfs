const std = @import("std");
pub const Id = 26;
const Errno = @import("../errno.zig").Errno;
const scheduler = @import("../task/scheduler.zig");
const TaskDescriptor = @import("../task/task.zig").TaskDescriptor;
const FileSet = @import("../task/file_set.zig");

pub fn do(oldfd: FileSet.Fd, newfd: FileSet.Fd) !FileSet.Fd {
    const file = try scheduler.get_current_task().files.get(oldfd);
    if (oldfd != newfd) {
        try scheduler.get_current_task().files.set(newfd, file.get_ref());
    }
    return oldfd;
}
