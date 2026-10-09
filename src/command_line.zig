const std = @import("std");
const memory = @import("memory.zig");
const multiboot = @import("multiboot.zig");
const multiboot2_h = @import("c_headers.zig").multiboot2_h;

root: @import("fs/vfs.zig").PartIdentifier,

const Self = @This();
var instance: ?Self = null;

fn get_slice() [:0]const u8 {
    const tag = multiboot.get_tag(multiboot2_h.MULTIBOOT_TAG_TYPE_CMDLINE) orelse @panic("no command line");
    const raw_str: [*:0]const u8 = @ptrCast(&tag.str);
    return std.mem.sliceTo(raw_str, 0);
}

pub fn get() Self {
    if (instance) |i|
        return i;
    const str = get_slice();
    var diag: std.zon.parse.Diagnostics = .{};
    instance = std.zon.parse.fromSlice(Self, memory.smallAlloc.allocator(), str, &diag, .{}) catch {
        std.log.err("Couldn't parse command line `{s}`: {f}", .{ str, diag });
        unreachable;
    };
    return instance.?;
}
