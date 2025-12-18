const tty = @import("../tty/tty.zig");
const scheduler = @import("../task/scheduler.zig");
const TaskDescriptor = @import("../task/task.zig").TaskDescriptor;
pub const Id = 19;

pub fn do(fd: TaskDescriptor.Fd, buf: [*]align(1) u8, len: usize) !usize {
    const file = scheduler.get_current_task().get_file(fd) orelse return error.EBADF;
    return file.read(buf[0..len]);
}
