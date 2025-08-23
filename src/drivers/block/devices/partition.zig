const std = @import("std");
const logger = std.log.scoped(.blockdev_partition);

const core = @import("../core.zig");
const types = core.types;
const translator = core.translator;

const DiskProvider = core.DiskProvider;
const BlockDevice = core.BlockDevice;
const BlockError = types.BlockError;
const DeviceType = types.DeviceType;
const Features = types.Features;
const Operations = types.Operations;
const BlockTranslator = core.BlockTranslator;

const STANDARD_BLOCK_SIZE = core.STANDARD_BLOCK_SIZE;

pub const PartitionInfo = struct {
    start_lba: u32, // Starting logical block address
    total_blocks: u32, // Size in logical blocks (512-byte blocks)
    active: bool = false, // Bootable flag
};

const vtable = Operations{
    .physical_io = partitionPhysicalIO,
    .flush = partitionFlush,
    .trim = partitionTrim,
    .media_changed = partitionMediaChanged,
    .revalidate = partitionRevalidate,
    .destroy = @ptrCast(&destroy),
};

const Self = @This();

base: BlockDevice,
allocator: std.mem.Allocator,
parent_device: *BlockDevice,
partition_info: PartitionInfo,

/// Create a partition device from a parent block device
pub fn init(
    allocator: std.mem.Allocator,
    parent_device: *BlockDevice,
    partition_info: PartitionInfo,
    major: u8,
    minor: u8,
) !Self {
    // Validate partition bounds
    if (partition_info.start_lba + partition_info.total_blocks > parent_device.total_blocks) {
        return BlockError.OutOfBounds;
    }

    if (partition_info.total_blocks == 0) {
        return BlockError.InvalidOperation;
    }

    // Create a translator that handles the partition offset and limits
    // We'll use the same physical block size as the parent device
    const physical_block_size = parent_device.getPhysicalBlockSize();
    const _translator = try translator.create(allocator, physical_block_size);
    errdefer _translator.deinit();

    // Configure the translator with partition-specific offset and limit
    _translator.logical_offset = partition_info.start_lba;
    _translator.logical_limit = partition_info.total_blocks;

    // Inherit features from parent but may restrict some
    const features = parent_device.features;
    // Partitions inherit the parent's capabilities but may be more restrictive
    // For example, if parent is read-only, partition must be read-only too

    const partition: Self = .{
        .base = .{
            .major = major,
            .minor = minor,
            .block_size = STANDARD_BLOCK_SIZE,
            .total_blocks = partition_info.total_blocks,
            .max_transfer = parent_device.max_transfer, // Inherit from parent
            .features = features,
            .vtable = &vtable,
            .translator = _translator,
        },
        .allocator = allocator,
        .parent_device = parent_device,
        .partition_info = partition_info,
    };

    return partition;
}

pub fn create(
    allocator: std.mem.Allocator,
    parent_device: *BlockDevice,
    partition_info: PartitionInfo,
    minor: u8,
) !*BlockDevice {
    const partition = try allocator.create(Self);
    errdefer allocator.destroy(partition);

    partition.* = try init(allocator, parent_device, partition_info, parent_device.major, minor);

    return &partition.base;
}

/// Physical I/O function - delegates to parent device
/// The translator will handle adding the partition offset automatically
fn partitionPhysicalIO(
    context: *anyopaque,
    physical_block: u32,
    count: u32,
    buffer: []u8,
    is_write: bool,
) BlockError!void {
    const device: *BlockDevice = @ptrCast(@alignCast(context));
    const self: *Self = @fieldParentPtr("base", device);

    // Delegate to parent device's physical I/O
    // The translator has already added the partition offset, so we can pass through directly
    return self.parent_device.vtable.physical_io(
        self.parent_device,
        physical_block,
        count,
        buffer,
        is_write,
    );
}

fn partitionFlush(dev: *BlockDevice) BlockError!void {
    const self: *Self = @fieldParentPtr("base", dev);

    // Delegate to parent device
    return self.parent_device.flush();
}

fn partitionTrim(dev: *BlockDevice, start_block: u32, count: u32) BlockError!void {
    const self: *Self = @fieldParentPtr("base", dev);

    // Convert partition-relative addresses to parent device addresses
    // The translator will handle this automatically when we call the parent's trim
    if (self.parent_device.features.trimable) {
        // We need to translate the addresses manually here since trim bypasses the normal I/O path
        const absolute_start = start_block + self.partition_info.start_lba;
        return self.parent_device.trim(absolute_start, count);
    }

    return BlockError.NotSupported;
}

fn partitionMediaChanged(dev: *BlockDevice) bool {
    const self: *Self = @fieldParentPtr("base", dev);

    // Delegate to parent device
    return self.parent_device.mediaChanged();
}

fn partitionRevalidate(dev: *BlockDevice) BlockError!void {
    const self: *Self = @fieldParentPtr("base", dev);

    // Delegate to parent device
    return self.parent_device.revalidate();
}

pub fn destroy(device: *BlockDevice) void {
    const self: *Self = @fieldParentPtr("base", device);
    self.allocator.destroy(self);
}

/// Get information about this partition
pub fn getPartitionInfo(self: *const Self) PartitionInfo {
    return self.partition_info;
}

/// Check if a logical block address is valid for this partition
pub fn isValidAddress(self: *const Self, lba: u32, count: u32) bool {
    return lba + count <= self.partition_info.size_block;
}

/// Convert partition-relative LBA to parent device LBA
pub fn toParentLBA(self: *const Self, partition_lba: u32) u32 {
    return partition_lba + self.partition_info.start_lba;
}

/// Convert parent device LBA to partition-relative LBA (if within partition bounds)
pub fn fromParentLBA(self: *const Self, parent_lba: u32) ?u32 {
    if (parent_lba < self.partition_info.start_lba) return null;
    const partition_lba = parent_lba - self.partition_info.start_lba;
    if (partition_lba >= self.partition_info.size_block) return null;
    return partition_lba;
}
