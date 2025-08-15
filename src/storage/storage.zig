const std = @import("std");
const logger = std.log.scoped(.storage);

pub const BlockDevice = @import("block_device.zig").BlockDevice;
pub const BlockError = @import("block_device.zig").BlockError;
pub const DeviceType = @import("block_device.zig").DeviceType;
pub const Features = @import("block_device.zig").Features;
pub const CachePolicy = @import("block_device.zig").CachePolicy;
pub const DeviceInfo = @import("block_device.zig").DeviceInfo;

pub const BufferCache = @import("buffer_cache.zig").BufferCache;
pub const Buffer = @import("buffer_cache.zig").Buffer;

pub const DeviceManager = @import("device_manager.zig").DeviceManager;

pub const IDEBlockDevice = @import("ide_device.zig").IDEBlockDevice;
pub const Partition = @import("ide_device.zig").Partition;

const ide = @import("../drivers/ide/ide.zig");
const allocator = @import("../memory.zig").smallAlloc.allocator();

var device_manager: DeviceManager = undefined;
var buffer_cache: BufferCache = undefined;
var initialized = false;
var ide_devices: std.ArrayList(*IDEBlockDevice) = undefined;

pub fn init() !void {
    if (initialized) return;

    logger.info("Initializing storage subsystem", .{});

    device_manager = DeviceManager.init();
    buffer_cache = try BufferCache.init();
    ide_devices = std.ArrayList(*IDEBlockDevice).init(allocator);

    try ide.init();

    try registerIDEDevices();

    device_manager.list();

    initialized = true;
    logger.info("Storage subsystem initialized", .{});
}

pub fn deinit() void {
    if (!initialized) return;

    logger.info("Shutting down storage subsystem", .{});

    flushAll() catch |err| {
        logger.err("Failed to flush cache: {}", .{err});
    };

    for (ide_devices.items) |device| {
        device_manager.unregister(device.base.getName()) catch {};
        device.destroy();
    }

    ide_devices.deinit();
    ide.deinit();
    buffer_cache.deinit();
    device_manager.deinit();

    initialized = false;
}

fn registerIDEDevices() !void {
    const drive_count = ide.getDriveCount();

    logger.info("Registering {} IDE drives as block devices", .{drive_count});

    for (0..drive_count) |i| {
        const ide_device = IDEBlockDevice.create(i) catch |err| {
            logger.err("Failed to create block device for drive {}: {}", .{ i, err });
            continue;
        };

        try ide_devices.append(ide_device);
        try device_manager.register(&ide_device.base);

        logger.info("Registered IDE drive {} as {s}", .{ i, ide_device.base.getName() });
    }
}

pub fn getManager() *DeviceManager {
    return &device_manager;
}

pub fn getCache() *BufferCache {
    return &buffer_cache;
}

pub fn findDevice(name: []const u8) ?*BlockDevice {
    return device_manager.find(name);
}

pub fn readCached(
    device_name: []const u8,
    start_block: u32,
    count: u32,
    buffer: []u8,
) BlockError!void {
    const dev = findDevice(device_name) orelse return BlockError.DeviceNotFound;

    if (count == 1) {
        const cached_buffer = try buffer_cache.get(dev, start_block);
        defer buffer_cache.put(cached_buffer);

        @memcpy(buffer[0..dev.block_size], cached_buffer.data[0..dev.block_size]);
        return;
    }

    try dev.read(start_block, count, buffer);
}

pub fn writeCached(
    device_name: []const u8,
    start_block: u64,
    count: u32,
    buffer: []const u8,
) BlockError!void {
    const dev = findDevice(device_name) orelse return BlockError.DeviceNotFound;

    if (count == 1) {
        const cached_buffer = try buffer_cache.get(dev, start_block);
        defer buffer_cache.put(cached_buffer);

        @memcpy(cached_buffer.data[0..dev.block_size], buffer[0..dev.block_size]);
        cached_buffer.markDirty();

        if (dev.cache_policy == .WriteThrough) {
            try buffer_cache.sync(cached_buffer);
        }
        return;
    }

    try dev.write(start_block, count, buffer);
}

pub fn flushDevice(device_name: []const u8) BlockError!void {
    const dev = findDevice(device_name) orelse return BlockError.DeviceNotFound;
    try buffer_cache.flushDevice(dev);
}

pub fn flushAll() BlockError!void {
    try buffer_cache.flushAll();
}

pub fn getDeviceInfo(device_name: []const u8) ?DeviceInfo {
    const dev = findDevice(device_name) orelse return null;
    return dev.getInfo();
}

pub fn formatSize(size_bytes: u64) struct { value: f64, unit: []const u8 } {
    const units = [_][]const u8{ "B", "KB", "MB", "GB", "TB" };
    var value = @as(f64, @floatFromInt(size_bytes));
    var unit_idx: usize = 0;

    while (value >= 1024 and unit_idx < units.len - 1) {
        value /= 1024;
        unit_idx += 1;
    }

    return .{ .value = value, .unit = units[unit_idx] };
}

pub fn printDeviceStats(device_name: []const u8) void {
    const dev = findDevice(device_name) orelse {
        logger.err("Device {s} not found", .{device_name});
        return;
    };

    const size = formatSize(dev.total_blocks * dev.block_size);

    logger.info("=== Device: {s} ===", .{device_name});
    logger.info("Type: {s}", .{@tagName(dev.device_type)});
    logger.info("Size: {d:.2} {s}", .{ size.value, size.unit });
    logger.info("Blocks: {} x {} bytes", .{ dev.total_blocks, dev.block_size });
    logger.info("Features:", .{});
    logger.info("  Readable: {}", .{dev.features.readable});
    logger.info("  Writable: {}", .{dev.features.writable});
    logger.info("  Removable: {}", .{dev.features.removable});
    logger.info("  Flush: {}", .{dev.features.supports_flush});
    logger.info("  TRIM: {}", .{dev.features.supports_trim});
    logger.info("Statistics:", .{});
    logger.info("  Reads: {} ({} blocks)", .{ dev.stats.reads_completed, dev.stats.blocks_read });
    logger.info("  Writes: {} ({} blocks)", .{ dev.stats.writes_completed, dev.stats.blocks_written });
    logger.info("  Errors: {}", .{dev.stats.errors});
    logger.info("  Cache hits: {}", .{dev.stats.cache_hits});
    logger.info("  Cache misses: {}", .{dev.stats.cache_misses});

    if (getDeviceInfo(device_name)) |info| {
        logger.info("Device Info:", .{});
        logger.info("  Vendor: {s}", .{info.vendor});
        logger.info("  Model: {s}", .{info.model});
        logger.info("  Firmware: {s}", .{info.firmware_version});
    }
}

pub const test_utils = struct {
    const tsc = @import("../drivers/tsc/tsc.zig");

    pub fn testBasicReadWrite(device_name: []const u8) !void {
        const device = findDevice(device_name) orelse {
            logger.err("Device {s} not found", .{device_name});
            return error.DeviceNotFound;
        };

        logger.info("=== Testing basic read/write on {s} ===", .{device_name});

        const test_block: u64 = 100;
        const buffer_size = device.block_size;

        const write_buffer = try allocator.alloc(u8, buffer_size);
        defer allocator.free(write_buffer);
        const read_buffer = try allocator.alloc(u8, buffer_size);
        defer allocator.free(read_buffer);

        logger.info("Test 1: Simple pattern", .{});
        for (write_buffer) |*b| b.* = 0xAA;
        try device.write(test_block, 1, write_buffer);
        try device.read(test_block, 1, read_buffer);

        for (read_buffer) |b| {
            if (b != 0xAA) {
                logger.err("Pattern verification failed!", .{});
                return error.VerificationFailed;
            }
        }
        logger.info("  Pattern test passed", .{});

        logger.info("Test 2: Random data", .{});
        var rng = std.Random.Xoroshiro128.init(12345);
        rng.fill(write_buffer);
        try device.write(test_block + 1, 1, write_buffer);
        try device.read(test_block + 1, 1, read_buffer);

        if (!std.mem.eql(u8, write_buffer, read_buffer)) {
            logger.err("Random data verification failed!", .{});
            return error.VerificationFailed;
        }
        logger.info("  Random data test passed", .{});

        logger.info("=== All basic tests passed ===", .{});
    }

    pub fn testCache(device_name: []const u8) !void {
        const device = findDevice(device_name) orelse {
            logger.err("Device {s} not found", .{device_name});
            return error.DeviceNotFound;
        };

        logger.info("=== Testing buffer cache on {s} ===", .{device_name});

        buffer_cache.stats = .{};

        const test_blocks = [_]u64{ 10, 20, 30, 40, 50 };

        logger.info("Test 1: Initial cache misses", .{});
        for (test_blocks) |block_num| {
            const buffer = try buffer_cache.get(device, block_num);
            defer buffer_cache.put(buffer);

            if (!buffer.isValid()) {
                logger.err("Buffer not valid after get!", .{});
                return error.CacheError;
            }
        }

        if (buffer_cache.stats.misses != test_blocks.len) {
            logger.err("Expected {} misses, got {}", .{ test_blocks.len, buffer_cache.stats.misses });
            return error.CacheError;
        }
        logger.info("  {} cache misses as expected", .{buffer_cache.stats.misses});

        logger.info("Test 2: Cache hits on repeated access", .{});
        const initial_hits = buffer_cache.stats.hits;
        for (test_blocks) |block_num| {
            const buffer = try buffer_cache.get(device, block_num);
            defer buffer_cache.put(buffer);
        }

        const new_hits = buffer_cache.stats.hits - initial_hits;
        if (new_hits != test_blocks.len) {
            logger.err("Expected {} hits, got {}", .{ test_blocks.len, new_hits });
            return error.CacheError;
        }
        logger.info("  {} cache hits as expected", .{new_hits});

        buffer_cache.printStats();
        logger.info("=== All cache tests passed ===", .{});
    }

    pub fn testPerformance(device_name: []const u8) !void {
        const device = findDevice(device_name) orelse {
            logger.err("Device {s} not found", .{device_name});
            return error.DeviceNotFound;
        };

        logger.info("=== Performance test on {s} ===", .{device_name});

        const test_size = 20 * 1024 * 1024;
        const blocks_per_mb = test_size / device.block_size;
        const start_block: u64 = 1000;

        const buffer = try allocator.alloc(u8, test_size);
        defer allocator.free(buffer);

        const test_mb: u64 = test_size / (1024 * 1024);
        logger.info("Sequential read test ({}MB):", .{test_mb});
        const read_start = tsc.get_time_us();
        try device.read(start_block, @truncate(blocks_per_mb), buffer);
        const read_end = tsc.get_time_us();
        const read_time_ms = (read_end - read_start) / 1000;
        const read_speed_mb: f32 = if (read_time_ms > 0)
            @as(f32, @floatFromInt(test_mb * 1000)) / @as(f32, @floatFromInt(read_time_ms))
        else
            0.0;
        logger.info("  Time: {} ms", .{read_time_ms});
        logger.info("  Speed: ~{d:.2} MB/s", .{read_speed_mb});

        if (device.features.writable) {
            logger.info("Sequential write test ({}MB):", .{test_mb});
            var rng = std.Random.Xoroshiro128.init(99999);
            rng.fill(buffer);
            const write_start = tsc.get_time_us();
            try device.write(start_block, @truncate(blocks_per_mb), buffer);
            const write_end = tsc.get_time_us();
            const write_time_ms = (write_end - write_start) / 1000;
            const write_speed_mb: f32 = if (write_time_ms > 0)
                @as(f32, @floatFromInt(test_mb * 1000)) / @as(f32, @floatFromInt(write_time_ms))
            else
                0.0;
            logger.info("  Time: {} ms", .{write_time_ms});
            logger.info("  Speed: ~{d:.2} MB/s", .{write_speed_mb});
        }

        logger.info("Random access test (100 blocks):", .{});
        const single_buffer = try allocator.alloc(u8, device.block_size);
        defer allocator.free(single_buffer);

        var rng = std.Random.Xoroshiro128.init(42);
        const random_start = tsc.get_time_us();
        for (0..100) |_| {
            const random_block = rng.random().int(u32) % 10000 + 1000;
            try device.read(random_block, 1, single_buffer);
        }
        const random_end = tsc.get_time_us();
        const random_time_ms = (random_end - random_start) / 1000;
        const iops = if (random_time_ms > 0) (100 * 1000) / random_time_ms else 0;
        logger.info("  Time: {} ms", .{random_time_ms});
        logger.info("  IOPS: ~{}", .{iops});

        logger.info("=== Performance test completed ===", .{});
    }

    pub fn runAllTests() !void {
        logger.info("=== Running Storage Tests ===", .{});

        device_manager.list();

        if (device_manager.getDeviceCount() == 0) {
            logger.warn("No block devices available for testing", .{});
            return;
        }

        const test_device = device_manager.getDeviceByIndex(0).?;
        const device_name = test_device.getName();

        logger.info("Using device {s} for testing", .{device_name});
        logger.warn("WARNING: This will write to blocks 100-1100 on the device!", .{});

        try testBasicReadWrite(device_name);
        try testCache(device_name);
        try testPerformance(device_name);

        logger.info("=== All tests completed successfully ===", .{});
    }
};
