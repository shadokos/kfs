const std = @import("std");
const ext2 = @import("ext2.zig");
const Partition = @import("../../device/block/partition.zig");
const FileSystem = @import("../filesystem.zig");
const SuperBlock = @import("../superblock.zig");
const Ext2Superblock = @import("superblock.zig");

pub fn static_init() !void {
    try @import("inode.zig").init_cache();
}

pub fn identify(part: *Partition) bool {
    var buffer = [1]u8{0} ** 1024;

    // Here we need to know the block size of this partition.
    part.read(2, 2, buffer[0..]) catch return false;

    const superblock: *align(1) ext2.Superblock = @ptrCast(&buffer);
    return superblock.signature == 0xEF53;
}

pub fn uuid(part: *Partition) ?u128 {
    var buffer = [1]u8{0} ** 1024;

    // Here we need to know the block size of this partition.
    part.read(2, 2, buffer[0..]) catch return null;

    const superblock: *align(1) ext2.Superblock = @ptrCast(&buffer);
    return if (superblock.version_major == 1) @byteSwap(superblock.extended.uuid) else null;
}

pub fn create(part: *Partition, allocator: std.mem.Allocator) *SuperBlock {
    std.log.debug("Ext2Superblock alignment: {}", .{@alignOf(Ext2Superblock)});
    const driver_sb: *Ext2Superblock = allocator.create(Ext2Superblock) catch @panic("todo");
    driver_sb.* = Ext2Superblock.init(part, allocator, false) catch @panic("todo");
    return driver_sb.ToVfs();
}

pub const fs: FileSystem = .{
    .identify = &identify,
    .create = &create,
    .name = "ext2",
    .uuid = &uuid,
};
