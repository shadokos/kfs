const scheduler = @import("../task/scheduler.zig");
const FileSet = @import("../task/file_set.zig");
const termios = @import("../tty/termios.zig");
const control = @import("../tty/ioctl.zig");

pub const Id = 37;

/// `actions` says when the change takes effect, POSIX 11.2. A plain integer,
/// since a value outside the set has to be answered with EINVAL.
pub fn do(fd: FileSet.Fd, actions: u32, new: *const termios.abi.Termios) !void {
    const request: control.Request = switch (actions) {
        @intFromEnum(control.SetAction.NOW) => .TCSETS,
        @intFromEnum(control.SetAction.DRAIN) => .TCSETSW,
        @intFromEnum(control.SetAction.FLUSH) => .TCSETSF,
        else => return error.EINVAL,
    };

    const file = try scheduler.get_current_task().files.get(fd);
    _ = try file.ioctl(@intFromEnum(request), @intFromPtr(new));
}
