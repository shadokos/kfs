const std = @import("std");
pub const Id = 54;
const Errno = @import("../errno.zig").Errno;
const scheduler = @import("../task/scheduler.zig");
const TaskDescriptor = @import("../task/task.zig").TaskDescriptor;
const FileSet = @import("../task/file_set.zig");
const vfs = @import("../fs/vfs.zig");

pub const Cmd = enum(usize) {
    DupFd,
};

pub fn do(fd : FileSet.Fd, cmd : Cmd, arg : usize) !usize {
    const task = scheduler.get_current_task();
    switch (cmd) {
        .DupFd => {
            const file = try task.files.get(fd);
            const ret : usize = @intCast(try task.files.add(file.get_ref(), @intCast(arg)));
            std.log.debug("cmd: {}, arg: {}, ret: {}", .{cmd, arg, ret});
            return ret;
        }
    }
    return 0;
}
