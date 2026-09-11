pub const Id = 56;
const std = @import("std");
const vfs = @import("../fs/vfs.zig");

pub fn do(path: [*:0]const u8) !void {
    const tnode = try vfs.resolve(std.mem.span(path));

    try tnode.unmount();
}