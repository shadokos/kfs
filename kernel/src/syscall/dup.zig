const std = @import("std");
pub const Id = 27;
const Errno = @import("../errno.zig").Errno;
const scheduler = @import("../task/scheduler.zig");
const TaskDescriptor = @import("../task/task.zig").TaskDescriptor;
const FileSet = @import("../task/file_set.zig");

pub fn do(fd: FileSet.Fd) !FileSet.Fd {
    const file = try scheduler.get_current_task().files.get(fd);
    return scheduler.get_current_task().files.add(file.get_ref());
}
