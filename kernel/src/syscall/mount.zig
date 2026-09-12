pub const Id = 55;
const std = @import("std");
const vfs = @import("../fs/vfs.zig");
const allocator = @import("../memory.zig").smallAlloc.allocator();

pub fn do(path: [*:0]const u8, identifier : [*:0]const u8, fs : ?[*:0]const u8) !void {
    const tnode = try vfs.resolve(std.mem.span(path));

    const part_identifier = std.zon.parse.fromSlice(vfs.PartIdentifier, allocator, std.mem.span(identifier), null, .{},) catch return error.EINVAL;

    std.log.debug("mounting {s} with {}", .{path, part_identifier});
    try vfs.mount(tnode, part_identifier, .{.fs = if (fs) |s| std.mem.span(s) else null});
}
