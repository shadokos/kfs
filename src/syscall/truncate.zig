const std = @import("std");
pub const Id = 21;
const Errno = @import("../errno.zig").Errno;
const vfs = @import("../fs/vfs.zig");
const Off = @import("../fs/file.zig").Off;
const scheduler = @import("../task/scheduler.zig");

// todo: should be Off
pub fn do(path: [*:0]const u8, off: u32) !void {
    const tnode = try vfs.resolve(std.mem.span(path));
    defer tnode.release();
    const inode = tnode.inode;
    try inode.truncate(off);
}
