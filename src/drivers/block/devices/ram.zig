const std = @import("std");
const logger = std.log.scoped(.blockdev_ram);

const core = @import("../core.zig");
const types = core.types;
const translator = core.translator;

const BlockDevice = core.BlockDevice;
const BlockError = types.BlockError;
const DeviceType = types.DeviceType;
const Features = types.Features;
const Operations = types.Operations;

const STANDARD_BLOCK_SIZE = core.STANDARD_BLOCK_SIZE;

base: BlockDevice,
allocator: std.mem.Allocator,
storage: []u8,

const ram_table = Operations{
    .physical_io = ramPhysicalIO,
    .flush = ramFlush,
    .trim = ramTrim,
    .media_changed = null,
    .revalidate = null,
};

const Self = @This();

/// Create a RAM disk with the specified physical block size
pub fn init(
    allocator: std.mem.Allocator,
    major: u8,
    minor: u8,
    size_mb: u32,
    physical_block_size: u32,
) !Self {
    // Validate the physical block size
    if (physical_block_size < STANDARD_BLOCK_SIZE or
        physical_block_size % STANDARD_BLOCK_SIZE != 0)
    {
        return BlockError.InvalidOperation;
    }

    const total_size = size_mb * 1024 * 1024;
    const physical_blocks = total_size / physical_block_size;
    const logical_blocks_per_physical = physical_block_size / STANDARD_BLOCK_SIZE;
    const total_logical_blocks = physical_blocks * logical_blocks_per_physical;

    // Allocate the storage
    const storage = try allocator.alignedAlloc(u8, 16, total_size);
    errdefer allocator.free(storage);

    logger.info("Storage length: {}", .{storage.len});

    // Initialize to zero
    @memset(storage, 0);

    // Create the appropriate translator
    const _translator = try translator.create(allocator, physical_block_size);
    errdefer _translator.deinit();

    const ramdisk: Self = .{
        .base = .{
            .major = major,
            .minor = minor,
            .block_size = STANDARD_BLOCK_SIZE,
            .total_blocks = total_logical_blocks,
            .max_transfer = 65535, // No practical limit for RAM
            .features = .{
                .readable = true,
                .writable = true,
                .removable = false,
                .flushable = true,
                .trimable = true,
            },
            .vtable = &ram_table,
            .translator = _translator,
        },
        .storage = storage,
        .allocator = allocator,
    };

    return ramdisk;
}

pub fn deinit(self: *Self) void {
    self.allocator.free(self.storage);
}

pub fn create(
    allocator: std.mem.Allocator,
    major: u8,
    minor: u8,
    size_mb: u32,
    physical_block_size: u32,
) !*BlockDevice {
    const ramdisk = try allocator.create(Self);
    errdefer allocator.destroy(ramdisk);

    ramdisk.* = try init(allocator, major, minor, size_mb, physical_block_size);

    // Return the BlockDevice pointer
    return &ramdisk.base;
}

pub fn destroy(dev: *BlockDevice) void {
    const self: *Self = @fieldParentPtr("base", dev);
    self.deinit();
    self.allocator.destroy(self);
}

/// Physical I/O function - this is where the magic happens
fn ramPhysicalIO(
    context: *anyopaque,
    physical_block: u32,
    count: u32,
    buffer: []u8,
    is_write: bool,
) BlockError!void {
    const device: *BlockDevice = @ptrCast(@alignCast(context));
    const self: *Self = @fieldParentPtr("base", device);

    const physical_block_size = self.base.translator.physical_block_size;
    // Calculate the offsets
    const offset = physical_block * physical_block_size;
    const size = count * physical_block_size;

    logger.info("{} + {} > {}", .{
        offset,
        size,
        self.storage.len,
    });
    // Check the limits
    if (offset + size > self.storage.len) {
        return BlockError.OutOfBounds;
    }

    if (buffer.len < size) {
        return BlockError.BufferTooSmall;
    }

    // Perform the operation
    if (is_write) {
        @memcpy(self.storage[offset .. offset + size], buffer[0..size]);
    } else {
        @memcpy(buffer[0..size], self.storage[offset .. offset + size]);
    }
}

fn ramFlush(dev: *BlockDevice) BlockError!void {
    _ = dev;
    // Nothing to do for a RAM disk
    logger.debug("RAM flush (no-op)", .{});
}

fn ramTrim(dev: *BlockDevice, start_block: u32, count: u32) BlockError!void {
    const self: *Self = @fieldParentPtr("base", dev);

    // Convert to physical addresses
    const physical_start = self.base.translator.vtable.logicalToPhysical(
        self.base.translator.context,
        start_block,
    );
    const range = self.base.translator.vtable.calculatePhysicalRange(
        self.base.translator.context,
        start_block,
        count,
    );

    const physical_block_size = self.base.translator.physical_block_size;
    // Zero out the TRIM areas
    const offset = physical_start * physical_block_size;
    const size = range.physical_count * physical_block_size;

    if (offset + size <= self.storage.len) {
        @memset(self.storage[offset .. offset + size], 0);
        logger.debug("RAM trim: {} logical blocks ({} physical) at {}", .{
            count,
            range.physical_count,
            start_block,
        });
    }
}
