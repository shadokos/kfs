const std = @import("std");
const tty = @import("../tty/tty.zig");
const scheduler = @import("../task/scheduler.zig");
const FileSet = @import("../task/file_set.zig");
pub const Id = 2;

pub fn do(fd: FileSet.Fd, buf: [*]align(1) const u8, len: usize) !usize {
    const file = try scheduler.get_current_task().files.get(fd);

    return file.write(buf[0..len]);
}
