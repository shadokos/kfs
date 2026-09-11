const scheduler = @import("../task/scheduler.zig");
const FileSet = @import("../task/file_set.zig");
const control = @import("../tty/ioctl.zig");

pub const Id = 45;

pub fn do(fd: FileSet.Fd, arg: u32) !void {
    const file = try scheduler.get_current_task().files.get(fd);
    _ = try file.ioctl(@intFromEnum(control.Request.TCDRAIN), arg);
}
