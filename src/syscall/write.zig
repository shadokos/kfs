const tty = @import("../tty/tty.zig");

pub const Id = 2;

pub fn do(buf: [*]align(1) const u8, len: usize) !usize {
    return tty.get_writer().write(buf[0..len]) catch unreachable;
}
