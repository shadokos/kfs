const tty = @import("../tty/tty.zig");
const scheduler = @import("../task/scheduler.zig");
const TaskDescriptor = @import("../task/task.zig").TaskDescriptor;
const FileSet = @import("../task/file_set.zig");
pub const Id = 19;

pub fn do(fd: FileSet.Fd, buf: [*]align(1) u8, len: usize) !usize {
    const file = try scheduler.get_current_task().files.get(fd);
    return file.read(buf[0..len]);
}
