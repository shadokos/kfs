const std = @import("std");
const Partition = @import("../../device/block/partition.zig");
const FileSystem = @import("../../fs/filesystem.zig");
const VfsSuperBlock = @import("../../fs/superblock.zig");
const Superblock = @import("superblock.zig");

pub fn static_init() !void {}

pub fn create(_: ?*Partition, _: std.mem.Allocator) *VfsSuperBlock {
    return &Superblock.instance;
}

pub const fs: FileSystem = .{
    .create = &create,
    .name = "rootfs",
    .virtual = true,
};
