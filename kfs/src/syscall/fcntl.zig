const std = @import("std");
pub const Id = 54;
const Errno = @import("../errno.zig").Errno;
const scheduler = @import("../task/scheduler.zig");
const TaskDescriptor = @import("../task/task.zig").TaskDescriptor;
const FileSet = @import("../task/file_set.zig");
const vfs = @import("../fs/vfs.zig");

pub fn do(fd : FileSet.Fd, cmd : usize, _ : usize) !usize {
    // const task = scheduler.get_current_task();
    std.log.debug("fcntl on fd {} called with command {}", .{fd, cmd});
    return 0;
}
