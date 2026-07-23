const std = @import("std");
const tty = @import("../tty/tty.zig");
const scheduler = @import("../task/scheduler.zig");
const TaskDescriptor = @import("../task/task.zig").TaskDescriptor;
pub const Id = 2;

pub fn do(fd: TaskDescriptor.Fd, buf: [*]align(1) const u8, len: usize) !usize {
    if (fd == 1) { // todo: implement tty char device
        return tty.get_writer().write(buf[0..len]) catch unreachable;
    }

    const file = scheduler.get_current_task().get_file(fd) orelse return error.EBADF;

    return file.write(buf[0..len]);
}
