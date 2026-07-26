const std = @import("std");
const tty = @import("../tty/tty.zig");
const scheduler = @import("../task/scheduler.zig");
const TaskDescriptor = @import("../task/task.zig").TaskDescriptor;
pub const Id = 2;

/// Write to the tty in red, restoring whatever color was current.
fn write_stderr(data: []const u8) usize {
    const current = tty.get_tty();
    const saved = current.current_color;
    defer current.current_color = saved;

    current.set_font_color(.red);
    return tty.get_writer().write(data) catch unreachable;
}

pub fn do(fd: TaskDescriptor.Fd, buf: [*]align(1) const u8, len: usize) !usize {
    // todo: implement tty char device
    switch (fd) {
        1 => return tty.get_writer().write(buf[0..len]) catch unreachable,
        2 => return write_stderr(buf[0..len]),
        else => {},
    }

    const file = scheduler.get_current_task().get_file(fd) orelse return error.EBADF;

    return file.write(buf[0..len]);
}
