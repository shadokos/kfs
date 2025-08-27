const std = @import("std");

const memory = @import("../../memory.zig");
const debug = @import("../../debug.zig");

const blk = @import("../../block/block.zig");
const STANDARD_BLOCK_SIZE = blk.STANDARD_BLOCK_SIZE;
const major_t = blk.major_t;
const minor_t = blk.minor_t;
const dev_t = blk.dev_t;
const GenDisk = blk.GenDisk;
const Partition = blk.Partition;
const IOType = blk.IOType;

const registry = @import("../../block/registry.zig");

const logger = std.log.scoped(.ramdisk);

const big_allocator = memory.bigAlloc.allocator();
const small_allocator = memory.smallAlloc.allocator();

const MAJOR: major_t = 1;

// Allow only 1 minor for ramdisk for the main partition.
// sub-partitions will be assigned to blkext
const MINORS: minor_t = 1;

const BrdData = struct {
    storage: []u8,
};

pub fn create_disk(minor: minor_t, size_mb: u32, sector_size: u32) !*GenDisk {
    if (sector_size < STANDARD_BLOCK_SIZE or
        sector_size % STANDARD_BLOCK_SIZE != 0)
        return blk.BlockError.InvalidOperation;

    const disk = try blk.GenDisk.create(MINORS);
    errdefer blk.GenDisk.destroy(disk);

    _ = try std.fmt.bufPrint(&disk.name, "ram{}", .{minor});

    const total_size = size_mb * 1024 * 1024;

    const data: *BrdData = try small_allocator.create(BrdData);
    errdefer small_allocator.destroy(data);

    data.storage = try big_allocator.alloc(u8, total_size);
    errdefer big_allocator.free(data.storage);

    disk.private_data = @ptrCast(@alignCast(data));

    disk.vtable = &brd_ops;
    disk.features = .{
        .readonly = false,
        .removable = false,
        .flushable = true,
        .trimable = true,
    };

    disk.max_transfer = std.math.maxInt(@TypeOf(disk.max_transfer)); // No practical limit for RAM
    disk.sector_size = sector_size;
    disk.major = MAJOR;
    disk.first_minor = minor;

    _ = disk.add_partition(0, total_size / STANDARD_BLOCK_SIZE) catch |e| {
        logger.debug("Failed to add whole partition: {s}", .{@errorName(e)});
        return e;
    };

    return disk;
}

const brd_ops = blk.Operations{
    .physical_io = physical_io,
    .destroy = destroy,
};

fn physical_io(
    context: *anyopaque,
    sector: u32,
    count: u32,
    buffer: []u8,
    operation: IOType,
) blk.BlockError!void {
    const partition: *Partition = @ptrCast(@alignCast(context));

    const sector_size = partition.translator.sector_size;
    // Calculate the offsets
    const offset = sector * sector_size;
    const size = count * sector_size;

    if (partition.disk.private_data == null) return blk.BlockError.IoError;

    const data: *BrdData = @ptrCast(@alignCast(partition.disk.private_data.?));

    // Check the limits
    if (offset + size > data.storage.len) {
        return blk.BlockError.OutOfBounds;
    }

    if (buffer.len < size) {
        return blk.BlockError.BufferTooSmall;
    }

    // Perform the operation
    switch (operation) {
        .Read => @memcpy(buffer[0..size], data.storage[offset .. offset + size]),
        .Write => @memcpy(data.storage[offset .. offset + size], buffer[0..size]),
    }
}

pub fn destroy(disk: *GenDisk) void {
    if (disk.private_data == null) return;
    const data: *BrdData = @ptrCast(@alignCast(disk.private_data));
    big_allocator.free(data.storage);
    small_allocator.destroy(data);
}

pub fn init() void {
    registry.register_block_dev(MAJOR, "ramdisk") catch {
        logger.warn("Failed to register ramdisk block device", .{});
        return;
    };
    logger.info("Ramdisk driver initialized", .{});

    // Only run test in debug mode
    if (std.log.defaultLogEnabled(.debug)) {
        test_disk();
    }
}

pub fn test_disk() void {
    const disk = create_disk(0, 1, 1024) catch {
        logger.debug("Failed to create test ramdisk", .{});
        return;
    };

    errdefer disk.destroy();

    _ = disk.add_partition(2, 10) catch |e| {
        logger.debug("Failed to add test partition: {s}", .{@errorName(e)});
        return;
    };

    logger.debug("Created test ramdisk: {s} (1MB)", .{disk.name});

    // Simple read/write test
    var buffer: [512]u8 = undefined;
    @memset(buffer[0..256], 0x01);
    @memset(buffer[256..512], 0x02);

    // Write first block of the first partition
    disk.partition_table.items[1].write(0, 1, &buffer) catch |e| {
        logger.debug("Test write failed: {s}", .{@errorName(e)});
        return;
    };

    // Read it back, from the whole disk (partition 0)
    @memset(buffer[0..], 0);
    disk.partition_table.items[0].read(2, 1, &buffer) catch |e| {
        logger.debug("Test read failed: {s}", .{@errorName(e)});
        return;
    };

    const start: usize = @intFromPtr(&buffer);
    debug.memory_dump(start, start + buffer.len, start);

    if (buffer[0] == 0x01 and buffer[256] == 0x02) {
        logger.debug("Ramdisk test passed", .{});
    } else {
        logger.debug("Ramdisk test failed", .{});
    }
}
