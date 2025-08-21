pub const types = @import("_core/types.zig");

pub const translator = @import("_core/translator.zig");
pub const BlockTranslator = translator.BlockTranslator;
pub const ScaledTranslator = translator.ScaledTranslator;
pub const IdentityTranslator = translator.IdentityTranslator;

pub const BlockDevice = @import("_core/block_device.zig");

// Standard logical block size for all block devices
pub const STANDARD_BLOCK_SIZE: u32 = 512;

const std = @import("std");
const logger = std.log.scoped(.blockdev);

pub fn init() void {
    @import("../../memory.zig").pageFrameAllocator.print();

    const allocator = @import("../../memory.zig").bigAlloc.allocator();

    // Simple block device creation for testing purposes
    // The block device management will mainly be handled by a Disk manager later
    const BdevRAM = @import("devices/ram.zig");
    // const PartitionDevice = @import("disks/partition.zig");
    // const PartitionManager = @import("partition_manager.zig").PartitionManager;

    const device = BdevRAM.create(
        allocator,
        0, // Major number
        0, // Minor number
        5, //  5 MB RAM disk
        512, // 512-byte physical block size
    ) catch |err| {
        logger.err("Failed to create RAM disk: {s}", .{@errorName(err)});
        return;
    };

    // Note: defers are called in reverse order
    defer allocator.destroy(@as(*BdevRAM, @fieldParentPtr("base", device)));
    defer device.deinit();

    logger.debug("RAM disk created:\nlogical blocks: {d} ({d} bytes)\nphysical blocks: {d} ({d} bytes)", .{
        device.total_blocks,
        device.block_size,
        device.getPhysicalBlockCount(),
        device.getPhysicalBlockSize(),
    });

    // Attempt to write and read some data at  a specific block
    //
    const block = 9;
    const buffer: []u8 = allocator.alloc(u8, 512 * 10) catch |err| {
        logger.err("Failed to allocate buffer for RAM disk: {s}", .{@errorName(err)});
        return;
    };
    defer allocator.free(buffer);

    for (buffer, 0..) |*byte, i| {
        byte.* = @truncate((i % 26) + 'A');
    }
    device.write(block, 1, buffer) catch |err| {
        logger.err("Failed to write to RAM disk: {s}", .{@errorName(err)});
        return;
    };
    logger.debug("Write successfully", .{});
    @memset(buffer, 0); // Clear buffer for read
    device.read(block, 1, buffer) catch |err| {
        logger.err("Failed to read from RAM disk: {s}", .{@errorName(err)});
        return;
    };
    logger.debug("Read successfully", .{});
    @import("../../debug.zig").memory_dump(
        @intFromPtr(buffer.ptr),
        @intFromPtr(buffer.ptr) + buffer.len,
        .Offset,
    );
}
