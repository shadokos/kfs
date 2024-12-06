const tty = @import("../tty/tty.zig");
// const err = @import("../errno.zig").Error;
const errno = @import("../task/errno.zig").Errno;

pub fn sys_write(buf: [*]const u8, len: u32) !usize {
    const writer = tty.get_writer();
    const _b: []const u8 = buf[0..len];
    return writer.write(_b) catch errno.EIO;
}
