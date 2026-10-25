const std = @import("std");
const logger = std.log.scoped(.block_device);

const registry = @import("registry.zig");
const core = @import("block.zig");
const STANDARD_BLOCK_SIZE = core.STANDARD_BLOCK_SIZE;
const BlockTranslator = core.BlockTranslator;
const Statistics = core.Statistics;
const BlockError = core.BlockError;
const Operations = core.Operations;

const types = @import("../types.zig");
const dev_t = types.dev_t;
const minor_t = types.minor_t;

pub const PART_NAME_LEN = 16;
const GenDisk = @import("gendisk.zig");
const PartitionType = @import("partitions/mbr.zig").PartitionType;

const errno = @import("../../errno.zig").Errno;

const Self = @This();

devt: dev_t = .{ .major = 0, .minor = 0 },
partno: minor_t,
disk: *GenDisk,
name: [PART_NAME_LEN:0]u8,
total_blocks: u32, // Total logical blocks
translator: *BlockTranslator, // Handles physical/logical translation
stats: Statistics = .{},
readonly: bool = false,
bootable: bool = false, // Boot flag from MBR
partition_type: PartitionType = .Empty,

/// Read logical blocks (always 512-byte blocks)
pub fn read(self: *Self, start_block: u32, count: u32, buffer: []u8) BlockError!void {
    if (buffer.len < count * STANDARD_BLOCK_SIZE) return BlockError.BufferTooSmall;
    if (start_block + count > self.total_blocks) return BlockError.OutOfBounds;
    if (self.disk.vtable == null) return BlockError.IoError;

    errdefer self.stats.errors += 1;

    // Use translator to handle the I/O
    try self.translator.read(
        start_block,
        count,
        buffer,
        self.disk.vtable.?.physical_io,
        self,
    );

    self.stats.reads_completed += 1;
    self.stats.blocks_read += count;
}

/// Write logical blocks (always 512-byte blocks)
pub fn write(self: *Self, start_block: u32, count: u32, buffer: []const u8) BlockError!void {
    if (buffer.len < count * STANDARD_BLOCK_SIZE) return BlockError.BufferTooSmall;
    if (start_block + count > self.total_blocks) return BlockError.OutOfBounds;
    if (self.disk.vtable == null) return BlockError.IoError;
    if (self.readonly or self.disk.features.readonly) return BlockError.WriteProtected;

    errdefer self.stats.errors += 1;

    // Use translator to handle the I/O
    try self.translator.write(start_block, count, buffer, self.disk.vtable.?.physical_io, self);

    self.stats.writes_completed += 1;
    self.stats.blocks_written += count;
}

/// Fill logical blocks with a repeating byte value.
pub fn fillBlock(self: *Self, start_block: u32, count: u32, value: u8) BlockError!void {
    var buf: [STANDARD_BLOCK_SIZE]u8 = undefined;
    @memset(&buf, value);
    for (0..count) |i| {
        try self.write(start_block + @as(u32, @intCast(i)), 1, &buf);
    }
}

/// Zero out logical blocks. Uses a comptime zero buffer to avoid runtime init.
pub fn zeroBlock(self: *Self, start_block: u32, count: u32) BlockError!void {
    const zero_buf = comptime [_]u8{0} ** STANDARD_BLOCK_SIZE;
    for (0..count) |i| {
        try self.write(start_block + @as(u32, @intCast(i)), 1, &zero_buf);
    }
}

pub fn alloc_devt(self: *Self) !dev_t {
    const disk = self.disk;

    if (self.partno < disk.minors) {
        self.devt = dev_t{ .major = disk.major, .minor = disk.first_minor + self.partno };
        return self.devt;
    }

    const idx: minor_t = try registry.blkext_alloc_id();

    self.devt = dev_t{ .major = registry.MAJOR, .minor = idx };
    return self.devt;
}

pub fn free_devt(self: *Self) void {
    if (self.devt.major == registry.MAJOR) {
        registry.blkext_free_id(self.devt);
        self.devt = .{ .major = 0, .minor = 0 };
    }
}

/// Cleanup resources when device is destroyed
pub fn destroy(self: *Self) void {
    self.translator.deinit();
    registry.blkext_free_id(self.devt);
}
