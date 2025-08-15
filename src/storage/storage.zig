// src/storage/storage.zig
const std = @import("std");
const logger = std.log.scoped(.storage);

pub const BlockDevice = @import("block_device.zig").BlockDevice;
pub const BlockError = @import("block_device.zig").BlockError;
pub const DeviceType = @import("block_device.zig").DeviceType;
pub const Features = @import("block_device.zig").Features;
pub const CachePolicy = @import("block_device.zig").CachePolicy;
pub const DeviceInfo = @import("block_device.zig").DeviceInfo;
pub const STANDARD_BLOCK_SIZE = @import("block_device.zig").STANDARD_BLOCK_SIZE;

pub const BufferCache = @import("buffer_cache.zig").BufferCache;
pub const Buffer = @import("buffer_cache.zig").Buffer;

pub const DeviceManager = @import("device_manager.zig").DeviceManager;

pub const IDEBlockDevice = @import("ide_device.zig").IDEBlockDevice;

const ide = @import("../drivers/ide/ide.zig");
const allocator = @import("../memory.zig").smallAlloc.allocator();

var device_manager: DeviceManager = undefined;
var buffer_cache: BufferCache = undefined;
var initialized = false;
var ide_devices: std.ArrayList(*IDEBlockDevice) = undefined;

pub fn init() !void {
    if (initialized) return;

    logger.info("Initializing storage subsystem", .{});
    logger.info("Standard block size: {} bytes", .{STANDARD_BLOCK_SIZE});

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

        const drive_info = ide.getDriveInfo(i).?;
        const physical_blocks = drive_info.capacity.sectors;
        const physical_block_size = drive_info.capacity.sector_size;
        const logical_blocks = ide_device.base.total_blocks;

        logger.info("Registered IDE drive {} as {s}:", .{ i, ide_device.base.getName() });
        logger.info("  Physical: {} blocks x {} bytes", .{ physical_blocks, physical_block_size });
        logger.info("  Logical:  {} blocks x {} bytes", .{ logical_blocks, STANDARD_BLOCK_SIZE });
        logger.info("  Translation ratio: {}:1", .{physical_block_size / STANDARD_BLOCK_SIZE});
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

    // Verify buffer size for standard blocks
    if (buffer.len < count * STANDARD_BLOCK_SIZE) {
        return BlockError.BufferTooSmall;
    }

    if (count == 1) {
        const cached_buffer = try buffer_cache.get(dev, start_block);
        defer buffer_cache.put(cached_buffer);

        @memcpy(buffer[0..STANDARD_BLOCK_SIZE], cached_buffer.data[0..STANDARD_BLOCK_SIZE]);
        return;
    }

    // For multiple blocks, use direct read
    try dev.read(start_block, count, buffer);
}

pub fn writeCached(
    device_name: []const u8,
    start_block: u64,
    count: u32,
    buffer: []const u8,
) BlockError!void {
    const dev = findDevice(device_name) orelse return BlockError.DeviceNotFound;

    // Verify buffer size for standard blocks
    if (buffer.len < count * STANDARD_BLOCK_SIZE) {
        return BlockError.BufferTooSmall;
    }

    if (count == 1) {
        const cached_buffer = try buffer_cache.get(dev, start_block);
        defer buffer_cache.put(cached_buffer);

        @memcpy(cached_buffer.data[0..STANDARD_BLOCK_SIZE], buffer[0..STANDARD_BLOCK_SIZE]);
        cached_buffer.markDirty();

        if (dev.cache_policy == .WriteThrough) {
            try buffer_cache.sync(cached_buffer);
        }
        return;
    }

    // For multiple blocks, use direct write
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

    const size = formatSize(dev.total_blocks * STANDARD_BLOCK_SIZE);

    logger.info("=== Device: {s} ===", .{device_name});
    logger.info("Type: {s}", .{@tagName(dev.device_type)});
    logger.info("Size: {d:.2} {s}", .{ size.value, size.unit });
    logger.info("Logical blocks: {} x {} bytes", .{ dev.total_blocks, STANDARD_BLOCK_SIZE });

    if (getDeviceInfo(device_name)) |info| {
        const physical_blocks = (dev.total_blocks * STANDARD_BLOCK_SIZE) / info.physical_block_size;
        logger.info("Physical blocks: {} x {} bytes", .{ physical_blocks, info.physical_block_size });
        logger.info("Translation ratio: {}:1", .{info.physical_block_size / STANDARD_BLOCK_SIZE});
    }

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
        logger.info("  Physical block size: {} bytes", .{info.physical_block_size});
    }
}

// Test utilities
pub const test_utils = struct {
    pub fn testBasicOperations(device_name: []const u8) !void {
        const device = findDevice(device_name) orelse {
            logger.err("Device {s} not found", .{device_name});
            return error.DeviceNotFound;
        };

        logger.info("=== Testing basic operations on {s} ===", .{device_name});
        logger.info("Block size: {} bytes (standard)", .{STANDARD_BLOCK_SIZE});

        const test_block: u64 = 100;

        // Test single block
        const buffer = try allocator.alloc(u8, STANDARD_BLOCK_SIZE);
        defer allocator.free(buffer);

        logger.info("Test 1: Single block read/write", .{});
        for (buffer) |*b| b.* = 0xAA;
        try device.write(test_block, 1, buffer);

        @memset(buffer, 0);
        try device.read(test_block, 1, buffer);

        for (buffer) |b| {
            if (b != 0xAA) {
                logger.err("Verification failed!", .{});
                return error.VerificationFailed;
            }
        }
        logger.info("  Passed", .{});

        // Test multiple blocks
        logger.info("Test 2: Multi-block operations", .{});
        const multi_buffer = try allocator.alloc(u8, STANDARD_BLOCK_SIZE * 4);
        defer allocator.free(multi_buffer);

        for (multi_buffer, 0..) |*b, i| {
            b.* = @truncate(i & 0xFF);
        }

        try device.write(test_block + 10, 4, multi_buffer);

        const verify_buffer = try allocator.alloc(u8, STANDARD_BLOCK_SIZE * 4);
        defer allocator.free(verify_buffer);

        try device.read(test_block + 10, 4, verify_buffer);

        if (!std.mem.eql(u8, multi_buffer, verify_buffer)) {
            logger.err("Multi-block verification failed!", .{});
            return error.VerificationFailed;
        }
        logger.info("  Passed", .{});

        logger.info("=== All basic tests passed ===", .{});
    }

    pub fn runAllTests() !void {
        logger.info("=== Running Storage Tests ===", .{});
        logger.info("Using standard block size: {} bytes", .{STANDARD_BLOCK_SIZE});

        device_manager.list();

        if (device_manager.getDeviceCount() == 0) {
            logger.warn("No block devices available for testing", .{});
            return;
        }

        const test_device = device_manager.getDeviceByIndex(0).?;
        const device_name = test_device.getName();

        logger.info("Using device {s} for testing", .{device_name});
        logger.warn("WARNING: This will write to blocks 100-200 on the device!", .{});

        try testBasicOperations(device_name);

        // Run translation tests if available
        const translation_test = @import("test_translation.zig");
        try translation_test.runTranslationTests();

        logger.info("=== All tests completed successfully ===", .{});
    }
};
