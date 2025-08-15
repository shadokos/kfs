// src/storage/test_translation.zig
const std = @import("std");
const storage = @import("storage.zig");
const BlockDevice = @import("block_device.zig").BlockDevice;
const STANDARD_BLOCK_SIZE = @import("block_device.zig").STANDARD_BLOCK_SIZE;
const logger = std.log.scoped(.translation_test);
const allocator = @import("../memory.zig").bigAlloc.allocator();

/// Test block size translation for ATAPI devices (2048-byte physical blocks)
pub fn testATAPITranslation(device_name: []const u8) !void {
    const device = storage.findDevice(device_name) orelse {
        logger.err("Device {s} not found", .{device_name});
        return error.DeviceNotFound;
    };

    logger.info("=== Testing ATAPI Block Translation on {s} ===", .{device_name});

    // Verify device is using standard block size
    if (device.block_size != STANDARD_BLOCK_SIZE) {
        logger.err("Device block size is {} instead of {}", .{ device.block_size, STANDARD_BLOCK_SIZE });
        return error.InvalidBlockSize;
    }

    // Get device info to check physical block size
    if (device.getInfo()) |info| {
        logger.info("Physical block size: {} bytes", .{info.physical_block_size});
        logger.info("Logical block size: {} bytes", .{device.block_size});
        logger.info("Total logical blocks: {}", .{device.total_blocks});
    }

    // Test 1: Read single logical block (512 bytes)
    logger.info("Test 1: Single logical block read", .{});
    {
        const buffer = try allocator.alloc(u8, STANDARD_BLOCK_SIZE);
        defer allocator.free(buffer);

        try device.read(0, 1, buffer);
        logger.info("  Successfully read 1 logical block", .{});
    }

    // Test 2: Read spanning multiple logical blocks within same physical block
    logger.info("Test 2: Read 3 logical blocks (within same physical block)", .{});
    {
        const buffer = try allocator.alloc(u8, STANDARD_BLOCK_SIZE * 3);
        defer allocator.free(buffer);

        try device.read(0, 3, buffer);
        logger.info("  Successfully read 3 logical blocks", .{});
    }

    // Test 3: Read spanning multiple physical blocks
    logger.info("Test 3: Read spanning physical blocks", .{});
    {
        // Read 5 logical blocks starting at logical block 3
        // This should span from physical block 0 to physical block 1
        const buffer = try allocator.alloc(u8, STANDARD_BLOCK_SIZE * 5);
        defer allocator.free(buffer);

        try device.read(3, 5, buffer);
        logger.info("  Successfully read 5 logical blocks spanning physical blocks", .{});
    }

    // Test 4: Write and verify (if device is writable)
    if (device.features.writable) {
        logger.info("Test 4: Write/Read verification with translation", .{});

        const test_blocks = 6;
        const write_buffer = try allocator.alloc(u8, STANDARD_BLOCK_SIZE * test_blocks);
        defer allocator.free(write_buffer);
        const read_buffer = try allocator.alloc(u8, STANDARD_BLOCK_SIZE * test_blocks);
        defer allocator.free(read_buffer);

        // Fill with pattern
        for (write_buffer, 0..) |*byte, i| {
            byte.* = @truncate(i % 256);
        }

        // Write at an unaligned position (logical block 5)
        try device.write(5, test_blocks, write_buffer);
        logger.info("  Wrote {} logical blocks at position 5", .{test_blocks});

        // Read back
        try device.read(5, test_blocks, read_buffer);

        // Verify
        if (!std.mem.eql(u8, write_buffer, read_buffer)) {
            logger.err("  Write/Read verification failed!", .{});
            return error.VerificationFailed;
        }

        logger.info("  Write/Read verification passed", .{});
    }

    logger.info("=== All translation tests passed ===", .{});
}

/// Test alignment and partial block operations
pub fn testPartialBlockOperations(device_name: []const u8) !void {
    const device = storage.findDevice(device_name) orelse {
        logger.err("Device {s} not found", .{device_name});
        return error.DeviceNotFound;
    };

    if (!device.features.writable) {
        logger.info("Device is not writable, skipping partial block tests", .{});
        return;
    }

    logger.info("=== Testing Partial Block Operations on {s} ===", .{device_name});

    // Test 1: Write single logical block at unaligned position
    logger.info("Test 1: Single block at unaligned position", .{});
    {
        const buffer = try allocator.alloc(u8, STANDARD_BLOCK_SIZE);
        defer allocator.free(buffer);

        // Fill with pattern
        for (buffer) |*byte| byte.* = 0xAB;

        // Write at logical block 7 (middle of physical block 1 for ATAPI)
        try device.write(7, 1, buffer);

        // Read back and verify
        const read_buffer = try allocator.alloc(u8, STANDARD_BLOCK_SIZE);
        defer allocator.free(read_buffer);
        try device.read(7, 1, read_buffer);

        if (!std.mem.eql(u8, buffer, read_buffer)) {
            logger.err("  Verification failed for single unaligned block", .{});
            return error.VerificationFailed;
        }

        logger.info("  Single unaligned block test passed", .{});
    }

    // Test 2: Write that starts and ends in middle of physical blocks
    logger.info("Test 2: Unaligned multi-block write", .{});
    {
        const start_block = 9; // Middle of physical block
        const count = 7; // Spans multiple physical blocks

        const buffer = try allocator.alloc(u8, STANDARD_BLOCK_SIZE * count);
        defer allocator.free(buffer);

        // Fill with incrementing pattern
        for (buffer, 0..) |*byte, i| {
            byte.* = @truncate(i & 0xFF);
        }

        try device.write(start_block, count, buffer);

        // Read back and verify
        const read_buffer = try allocator.alloc(u8, STANDARD_BLOCK_SIZE * count);
        defer allocator.free(read_buffer);
        try device.read(start_block, count, read_buffer);

        if (!std.mem.eql(u8, buffer, read_buffer)) {
            logger.err("  Verification failed for unaligned multi-block", .{});
            return error.VerificationFailed;
        }

        logger.info("  Unaligned multi-block test passed", .{});
    }

    // Test 3: Verify surrounding blocks weren't corrupted
    logger.info("Test 3: Check for corruption of surrounding blocks", .{});
    {
        // Write known pattern to blocks before and after our test area
        const guard_buffer = try allocator.alloc(u8, STANDARD_BLOCK_SIZE);
        defer allocator.free(guard_buffer);

        for (guard_buffer) |*byte| byte.* = 0xFF;

        try device.write(8, 1, guard_buffer); // Before
        try device.write(16, 1, guard_buffer); // After

        // Do a partial write in the middle
        const test_buffer = try allocator.alloc(u8, STANDARD_BLOCK_SIZE * 2);
        defer allocator.free(test_buffer);
        for (test_buffer) |*byte| byte.* = 0x55;

        try device.write(10, 2, test_buffer);

        // Verify guards are intact
        const verify_buffer = try allocator.alloc(u8, STANDARD_BLOCK_SIZE);
        defer allocator.free(verify_buffer);

        try device.read(8, 1, verify_buffer);
        for (verify_buffer) |byte| {
            if (byte != 0xFF) {
                logger.err("  Before-guard corrupted!", .{});
                return error.GuardCorrupted;
            }
        }

        try device.read(16, 1, verify_buffer);
        for (verify_buffer) |byte| {
            if (byte != 0xFF) {
                logger.err("  After-guard corrupted!", .{});
                return error.GuardCorrupted;
            }
        }

        logger.info("  Guard blocks intact", .{});
    }

    logger.info("=== All partial block tests passed ===", .{});
}

/// Performance comparison between aligned and unaligned operations
pub fn testTranslationPerformance(device_name: []const u8) !void {
    const device = storage.findDevice(device_name) orelse {
        logger.err("Device {s} not found", .{device_name});
        return error.DeviceNotFound;
    };

    logger.info("=== Testing Translation Performance on {s} ===", .{device_name});

    const tsc = @import("../drivers/tsc/tsc.zig");
    const test_size = 64; // Number of logical blocks

    const buffer = try allocator.alloc(u8, STANDARD_BLOCK_SIZE * test_size);
    defer allocator.free(buffer);

    // Test aligned read (starts at physical block boundary)
    logger.info("Aligned read ({} logical blocks):", .{test_size});
    const aligned_start = tsc.get_time_us();
    try device.read(0, test_size, buffer);
    const aligned_time = tsc.get_time_us() - aligned_start;
    logger.info("  Time: {} µs", .{aligned_time});

    // Test unaligned read (starts in middle of physical block)
    logger.info("Unaligned read ({} logical blocks):", .{test_size});
    const unaligned_start = tsc.get_time_us();
    try device.read(1, test_size, buffer);
    const unaligned_time = tsc.get_time_us() - unaligned_start;
    logger.info("  Time: {} µs", .{unaligned_time});

    const overhead_percent = if (aligned_time > 0)
        ((unaligned_time - aligned_time) * 100) / aligned_time
    else
        0;

    logger.info("Translation overhead: {}%", .{overhead_percent});

    logger.info("=== Performance test completed ===", .{});
}

/// Run all translation tests
pub fn runTranslationTests() !void {
    logger.info("=== Running Block Size Translation Tests ===", .{});

    const manager = storage.getManager();
    if (manager.getDeviceCount() == 0) {
        logger.warn("No devices available for testing", .{});
        return;
    }

    // Find an ATAPI device if available
    var atapi_device: ?*BlockDevice = null;
    var ata_device: ?*BlockDevice = null;

    for (0..manager.getDeviceCount()) |i| {
        const device = manager.getDeviceByIndex(i).?;
        if (device.getInfo()) |info| {
            if (info.physical_block_size == 2048) {
                atapi_device = device;
                logger.info("Found ATAPI device: {s}", .{device.getName()});
            } else if (info.physical_block_size == 512) {
                ata_device = device;
                logger.info("Found ATA device: {s}", .{device.getName()});
            }
        }
    }

    if (atapi_device) |device| {
        logger.info("\nTesting ATAPI device with 2048-byte physical blocks", .{});
        try testATAPITranslation(device.getName());
        try testPartialBlockOperations(device.getName());
        try testTranslationPerformance(device.getName());
    } else {
        logger.info("No ATAPI device found, translation tests limited", .{});
    }

    if (ata_device) |device| {
        logger.info("\nTesting ATA device with 512-byte physical blocks", .{});
        logger.info("(Should have 1:1 mapping, no translation overhead)", .{});
        try testPartialBlockOperations(device.getName());
        try testTranslationPerformance(device.getName());
    }

    logger.info("=== All translation tests completed ===", .{});
}
