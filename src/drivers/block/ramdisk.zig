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

const registry = @import("../../block/registry.zig");

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
    // errdefer blk.GenDisk.destroy(disk);

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

    disk.max_transfer = 65535; // No practical limit for RAM
    disk.sector_size = sector_size;
    disk.major = MAJOR;
    disk.first_minor = minor;

    _ = disk.add_partition(0, total_size / STANDARD_BLOCK_SIZE) catch |e| {
        std.log.debug("Failed to add whole partition: {s}", .{@errorName(e)});
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
    is_write: bool,
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
    if (is_write) {
        @memcpy(data.storage[offset .. offset + size], buffer[0..size]);
    } else {
        @memcpy(buffer[0..size], data.storage[offset .. offset + size]);
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
        std.log.debug("Failed to register ramdisk block device", .{});
        return;
    };
    test_disk();
}

pub fn test_disk() void {
    memory.pageFrameAllocator.print();
    const disk = create_disk(0, 1, 1024) catch {
        std.log.debug("Failed to create ramdisk", .{});
        return;
    };

    defer memory.pageFrameAllocator.print();
    defer disk.destroy();

    _ = disk.add_partition(1, 10) catch |e| {
        std.log.debug("Failed to add partition: {s}", .{@errorName(e)});
        return;
    };
    _ = disk.add_partition(10, 10) catch |e| {
        std.log.debug("Failed to add partition: {s}", .{@errorName(e)});
        return;
    };

    const data: *BrdData = @ptrCast(@alignCast(disk.private_data));
    @memset(data.storage[512..], 0x42);
    std.log.debug("Created ramdisk: \"{s}\" ({} len)", .{ disk.name, data.storage.len });

    var buffer: [2048]u8 = undefined;
    std.log.debug("\nread from {s} ({d})", .{
        disk.partition_table.items[0].name,
        disk.partition_table.items[0].devt.toInt(),
    });
    disk.partition_table.items[0].read(0, 4, &buffer) catch |e| {
        std.log.warn("Failed to read from {s}: {s}", .{ disk.partition_table.items[0].name, @errorName(e) });
        return;
    };
    const start: usize = @intFromPtr(&buffer);
    const end = start + buffer.len;

    debug.memory_dump(start, end, start);

    @memset(buffer[0..], 0);
    @memset(buffer[0..256], 0x01);
    @memset(buffer[256..512], 0x02);
    std.log.debug("\nwrite to {s} ({d})", .{
        disk.partition_table.items[1].name,
        disk.partition_table.items[1].devt.toInt(),
    });
    disk.partition_table.items[1].write(0, 1, &buffer) catch |e| {
        std.log.warn("Failed to write to {s}: {s}", .{ disk.partition_table.items[1].name, @errorName(e) });
        return;
    };

    @memset(buffer[0..], 0);
    std.log.debug("\nread from {s} ({d})", .{
        disk.partition_table.items[1].name,
        disk.partition_table.items[1].devt.toInt(),
    });
    disk.partition_table.items[1].read(0, 4, &buffer) catch |e| {
        std.log.warn("Failed to read from {s}: {s}", .{ disk.partition_table.items[1].name, @errorName(e) });
        return;
    };
    const start2: usize = @intFromPtr(&buffer);
    const end2 = start2 + buffer.len;
    debug.memory_dump(start2, end2, start2);

    const start3: usize = @intFromPtr(data.storage.ptr);
    const end3 = start3 + data.storage.len;
    std.log.debug("\ndump ramdisk storage", .{});
    debug.memory_dump(start3, end3, start3);

    registry.show_partitions(@import("../../tty/tty.zig").get_writer());
}
