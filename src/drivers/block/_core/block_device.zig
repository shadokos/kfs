const std = @import("std");
const logger = std.log.scoped(.block_device);

const core = @import("../core.zig");
const types = core.types;

const DeviceType = types.DeviceType;
const Features = types.Features;
const CachePolicy = types.CachePolicy;
const Statistics = types.Statistics;
const BlockError = types.BlockError;
const Operations = types.Operations;
const BlockTranslator = core.BlockTranslator;
const STANDARD_BLOCK_SIZE = core.STANDARD_BLOCK_SIZE;

major: u8,
minor: u8,
vtable: *const Operations,
block_size: u32 = STANDARD_BLOCK_SIZE, // Always standard size for logical interface
total_blocks: u32, // Total logical blocks
max_transfer: u32, // Maximum logical blocks per transfer
features: Features,
translator: *BlockTranslator, // Handles physical/logical translation
stats: Statistics = .{},

const Self = @This();

/// Read logical blocks (always 512-byte blocks)
pub fn read(self: *Self, start_block: u32, count: u32, buffer: []u8) BlockError!void {
    // TODO, maybe not return an error when out of bounds, just read as much as possible
    if (buffer.len < count * STANDARD_BLOCK_SIZE) return BlockError.BufferTooSmall;
    if (start_block + count > self.total_blocks) return BlockError.OutOfBounds;
    if (!self.features.readable) return BlockError.NotSupported;

    errdefer self.stats.errors += 1;

    // Use translator to handle the I/O
    try self.translator.read(
        start_block,
        count,
        buffer,
        self.vtable.physical_io,
        self,
    );

    self.stats.reads_completed += 1;
    self.stats.blocks_read += count;
}

/// Write logical blocks (always 512-byte blocks)
pub fn write(self: *Self, start_block: u32, count: u32, buffer: []const u8) BlockError!void {
    // TODO, maybe not return an error when out of bounds, just read as much as possible
    if (buffer.len < count * STANDARD_BLOCK_SIZE) return BlockError.BufferTooSmall;
    if (start_block + count > self.total_blocks) return BlockError.OutOfBounds;
    if (!self.features.writable) return BlockError.WriteProtected;

    errdefer self.stats.errors += 1;

    // Use translator to handle the I/O
    try self.translator.write(start_block, count, buffer, self.vtable.physical_io, self);

    self.stats.writes_completed += 1;
    self.stats.blocks_written += count;
}

pub fn flush(self: *Self) BlockError!void {
    if (self.vtable.flush) |flush_fn| {
        errdefer self.stats.errors += 1;
        try flush_fn(self);
    }
}

pub fn trim(self: *Self, start_block: u32, count: u32) BlockError!void {
    if (!self.features.trimable) return BlockError.NotSupported;
    if (self.vtable.trim) |trim_fn| {
        errdefer self.stats.errors += 1;
        try trim_fn(self, start_block, count);
    }
}

pub fn mediaChanged(self: *Self) bool {
    if (self.vtable.media_changed) |media_changed_fn| {
        return media_changed_fn(self);
    }
    return false;
}

pub fn revalidate(self: *Self) BlockError!void {
    if (self.vtable.revalidate) |revalidate_fn| {
        errdefer self.stats.errors += 1;
        try revalidate_fn(self);
    }
}

/// Get the physical block size of the underlying device
pub fn getPhysicalBlockSize(self: *const Self) u32 {
    return self.translator.physical_block_size;
}

/// Get the total number of physical blocks
pub fn getPhysicalBlockCount(self: *const Self) u64 {
    const logical_per_physical = self.translator.physical_block_size / STANDARD_BLOCK_SIZE;
    return self.total_blocks / logical_per_physical;
}

/// Cleanup resources when device is destroyed
pub fn deinit(self: *Self) void {
    self.translator.deinit();
    if (self.vtable.deinit) |deinit_fn| {
        deinit_fn(self);
    }
}
