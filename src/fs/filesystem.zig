const std = @import("std");
const block = @import("../device/block/block.zig");
const SuperBlock = @import("superblock.zig");

identify: *const fn (*block.Partition) bool = &Generic.identify,
uuid: *const fn (*block.Partition) ?SuperBlock.UUID = &Generic.uuid,
create: *const fn (*block.Partition, std.mem.Allocator) *SuperBlock,
name: []const u8,

const Generic = struct {
    pub fn identify(_: *block.Partition) bool {
        return false;
    }
    pub fn uuid(_: *block.Partition) ?SuperBlock.UUID {
        return null;
    }
};
