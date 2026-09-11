const scheduler = @import("../task/scheduler.zig");
const FileSet = @import("../task/file_set.zig");
const termios = @import("../tty/termios.zig");
const control = @import("../tty/ioctl.zig");

pub const Id = 36;

pub fn do(fd: FileSet.Fd, out: *termios.abi.Termios) !void {
    const file = try scheduler.get_current_task().files.get(fd);
    _ = try file.ioctl(@intFromEnum(control.Request.TCGETS), @intFromPtr(out));
}
