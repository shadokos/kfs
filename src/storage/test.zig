const std = @import("std");
const storage = @import("storage.zig");
const logger = std.log.scoped(.storage_test);
const tsc = @import("../drivers/tsc/tsc.zig");

const allocator = @import("../memory.zig").bigAlloc.allocator();

pub fn fillPattern(buffer: []u8, pattern: u8) void {
    for (buffer) |*byte| {
        byte.* = pattern;
    }
}

pub fn verifyPattern(buffer: []const u8, pattern: u8) bool {
    for (buffer) |byte| {
        if (byte != pattern) return false;
    }
    return true;
}

pub fn generateTestData(buffer: []u8, seed: u32) void {
    var rng = std.Random.Xoroshiro128.init(seed);
    rng.fill(buffer);
}

pub fn verifyTestData(buffer: []const u8, seed: u32) bool {
    const temp = allocator.alloc(u8, buffer.len) catch return false;
    defer allocator.free(temp);

    generateTestData(temp, seed);
    return std.mem.eql(u8, buffer, temp);
}

pub fn testBasicReadWrite(device_name: []const u8) !void {
    const device = storage.findDevice(device_name) orelse {
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
    fillPattern(write_buffer, 0xAA);
    try device.write(test_block, 1, write_buffer);
    try device.read(test_block, 1, read_buffer);

    if (!verifyPattern(read_buffer, 0xAA)) {
        logger.err("Pattern verification failed!", .{});
        return error.VerificationFailed;
    }
    logger.info("  Pattern test passed", .{});

    logger.info("Test 2: Random data", .{});
    generateTestData(write_buffer, 12345);
    try device.write(test_block + 1, 1, write_buffer);
    try device.read(test_block + 1, 1, read_buffer);

    if (!verifyTestData(read_buffer, 12345)) {
        logger.err("Random data verification failed!", .{});
        return error.VerificationFailed;
    }
    logger.info("  Random data test passed", .{});

    if (device.total_blocks > test_block + 10) {
        logger.info("Test 3: Multi-block operation", .{});
        const multi_blocks = 5;
        const multi_buffer = try allocator.alloc(u8, buffer_size * multi_blocks);
        defer allocator.free(multi_buffer);

        generateTestData(multi_buffer, 54321);
        try device.write(test_block + 5, multi_blocks, multi_buffer);

        const verify_buffer = try allocator.alloc(u8, buffer_size * multi_blocks);
        defer allocator.free(verify_buffer);
        try device.read(test_block + 5, multi_blocks, verify_buffer);

        if (!std.mem.eql(u8, multi_buffer, verify_buffer)) {
            logger.err("Multi-block verification failed!", .{});
            return error.VerificationFailed;
        }
        logger.info("  Multi-block test passed", .{});
    }

    logger.info("=== All basic tests passed ===", .{});
}

pub fn testCache(device_name: []const u8) !void {
    const device = storage.findDevice(device_name) orelse {
        logger.err("Device {s} not found", .{device_name});
        return error.DeviceNotFound;
    };

    const cache = storage.getCache();

    logger.info("=== Testing buffer cache on {s} ===", .{device_name});

    cache.stats = .{};

    const test_blocks = [_]u64{ 10, 20, 30, 40, 50 };

    logger.info("Test 1: Initial cache misses", .{});
    for (test_blocks) |block_num| {
        const buffer = try cache.get(device, block_num);
        defer cache.put(buffer);

        if (!buffer.isValid()) {
            logger.err("Buffer not valid after get!", .{});
            return error.CacheError;
        }
    }

    if (cache.stats.misses != test_blocks.len) {
        logger.err("Expected {} misses, got {}", .{ test_blocks.len, cache.stats.misses });
        return error.CacheError;
    }
    logger.info("  {} cache misses as expected", .{cache.stats.misses});

    logger.info("Test 2: Cache hits on repeated access", .{});
    const initial_hits = cache.stats.hits;
    for (test_blocks) |block_num| {
        const buffer = try cache.get(device, block_num);
        defer cache.put(buffer);
    }

    const new_hits = cache.stats.hits - initial_hits;
    if (new_hits != test_blocks.len) {
        logger.err("Expected {} hits, got {}", .{ test_blocks.len, new_hits });
        return error.CacheError;
    }
    logger.info("  {} cache hits as expected", .{new_hits});

    logger.info("Test 3: Dirty buffer handling", .{});
    {
        const buffer = try cache.get(device, 60);
        defer cache.put(buffer);

        fillPattern(buffer.data[0..device.block_size], 0xFF);
        buffer.markDirty();

        try cache.sync(buffer);
    }

    if (cache.stats.writebacks == 0) {
        logger.err("No writebacks recorded!", .{});
        return error.CacheError;
    }
    logger.info("  Writeback triggered for dirty buffer", .{});

    logger.info("Test 4: Verify cached write", .{});
    {
        const buffer = try cache.get(device, 60);
        defer cache.put(buffer);

        if (!verifyPattern(buffer.data[0..device.block_size], 0xFF)) {
            logger.err("Cached write verification failed!", .{});
            return error.VerificationFailed;
        }
    }
    logger.info("  Cached write verified", .{});

    cache.printStats();
    logger.info("=== All cache tests passed ===", .{});
}

pub fn testPerformance(device_name: []const u8) !void {
    const device = storage.findDevice(device_name) orelse {
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
        generateTestData(buffer, 99999);
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

    logger.info("Device statistics:", .{});
    logger.info("  Reads: {}", .{device.stats.reads_completed});
    logger.info("  Writes: {}", .{device.stats.writes_completed});
    logger.info("  Blocks read: {}", .{device.stats.blocks_read});
    logger.info("  Blocks written: {}", .{device.stats.blocks_written});
    logger.info("  Errors: {}", .{device.stats.errors});

    logger.info("=== Performance test completed ===", .{});
}

pub fn testCachedOperations() !void {
    logger.info("=== Testing cached operations ===", .{});

    const manager = storage.getManager();
    if (manager.getDeviceCount() == 0) {
        logger.warn("No devices available for testing", .{});
        return;
    }

    const device = manager.getDeviceByIndex(0).?;
    const device_name = device.getName();

    const buffer_size = device.block_size;
    const write_buffer = try allocator.alloc(u8, buffer_size);
    defer allocator.free(write_buffer);
    const read_buffer = try allocator.alloc(u8, buffer_size);
    defer allocator.free(read_buffer);

    logger.info("Test 1: Cached single-block read", .{});
    try storage.readCached(device_name, 200, 1, read_buffer);
    logger.info("  Read completed", .{});

    logger.info("Test 2: Cached single-block write", .{});
    fillPattern(write_buffer, 0xCD);
    try storage.writeCached(device_name, 201, 1, write_buffer);
    logger.info("  Write completed", .{});

    logger.info("Test 3: Verify cached write", .{});
    try storage.readCached(device_name, 201, 1, read_buffer);
    if (!verifyPattern(read_buffer, 0xCD)) {
        logger.err("Cached write verification failed!", .{});
        return error.VerificationFailed;
    }
    logger.info("  Verification passed", .{});

    logger.info("Test 4: Flush device", .{});
    try storage.flushDevice(device_name);
    logger.info("  Device flushed", .{});

    logger.info("=== Cached operations test passed ===", .{});
}

pub fn runAllTests() !void {
    logger.info("=== Running Storage Tests ===", .{});

    const manager = storage.getManager();
    manager.list();

    if (manager.getDeviceCount() == 0) {
        logger.warn("No block devices available for testing", .{});
        return;
    }

    const test_device = manager.getDeviceByIndex(0).?;
    const device_name = test_device.getName();

    logger.info("Using device {s} for testing", .{device_name});
    logger.warn("WARNING: This will write to blocks 100-1100 on the device!", .{});

    try testBasicReadWrite(device_name);
    try testCache(device_name);
    try testCachedOperations();
    try testPerformance(device_name);

    logger.info("=== All tests completed successfully ===", .{});
}
