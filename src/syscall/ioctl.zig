const scheduler = @import("../task/scheduler.zig");
const FileSet = @import("../task/file_set.zig");

pub const Id = 42;

/// Device control. Only for the three requests mlibc routes through ioctl:
/// TIOCGPGRP, TIOCSPGRP and TIOCGSID. Everything else has its own syscall.
pub fn do(fd: FileSet.Fd, request: u32, arg: usize) !usize {
    const file = try scheduler.get_current_task().files.get(fd);
    return file.ioctl(request, arg);
}
