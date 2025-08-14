const std = @import("std");
const logger = std.log.scoped(.block_device);

pub const BlockDevice = @import("device.zig");
pub const BlockDeviceManager = @import("device_manager.zig");
pub const BufferCache = @import("buffer_cache.zig");
pub const Buffer = @import("buffer_cache.zig").Buffer;

pub const ide_adapter = @import("ide_adapter.zig");
pub const block_device_test = @import("test.zig");

// === ERROR TYPES ===

pub const Error = error{
    DeviceNotFound,
    DeviceExists,
    BufferTooSmall,
    OutOfBounds,
    WriteProtected,
    NotSupported,
    IoError,
    NoFreeBuffers,
    InvalidOperation,
    MediaNotPresent,
    DeviceBusy,
    CorruptedData,
};

// === INITIALIZATION ===

var initialized = false;

/// Initialize the block device subsystem
pub fn init() !void {
    if (initialized) return;

    logger.info("Initializing block device subsystem", .{});

    // Initialize core components
    try BlockDevice.init();

    // Initialize IDE adapter (registers IDE drives as block devices)
    try ide_adapter.init();

    // List all registered devices
    getManager().list();

    initialized = true;
    logger.info("Block device subsystem initialized", .{});
}

/// Shutdown the block device subsystem
pub fn deinit() void {
    if (!initialized) return;

    logger.info("Shutting down block device subsystem", .{});

    // Flush all cached data
    getCache().flushAll() catch |err| {
        logger.err("Failed to flush cache: {}", .{err});
    };

    // Deinitialize adapters
    ide_adapter.deinit();

    // Deinitialize core components
    BlockDevice.deinit();

    initialized = false;
}

// === PUBLIC API ===

/// Get the global block device manager
pub fn getManager() *BlockDeviceManager {
    return BlockDevice.getManager();
}

/// Get the global buffer cache
pub fn getCache() *BufferCache {
    return BlockDevice.getCache();
}

/// Find a block device by name
pub fn findDevice(name: []const u8) ?*BlockDevice {
    return getManager().find(name);
}

/// Read blocks from a device (with caching)
pub fn readCached(
    device_name: []const u8,
    start_block: u64,
    count: u32,
    buffer: []u8,
) Error!void {
    const dev = findDevice(device_name) orelse return Error.DeviceNotFound;
    const cache = getCache();

    // For single block reads, use cache
    if (count == 1) {
        const cached_buffer = try cache.get(dev, start_block);
        defer cache.put(cached_buffer);

        @memcpy(buffer[0..dev.block_size], cached_buffer.data[0..dev.block_size]);
        return;
    }

    // For multi-block reads, bypass cache for now
    // TODO: Implement read-ahead and multi-block caching
    try dev.read(start_block, count, buffer);
}

/// Write blocks to a device (with caching)
pub fn writeCached(
    device_name: []const u8,
    start_block: u64,
    count: u32,
    buffer: []const u8,
) Error!void {
    const dev = findDevice(device_name) orelse return Error.DeviceNotFound;
    const cache = getCache();

    // For single block writes, use cache
    if (count == 1) {
        const cached_buffer = try cache.get(dev, start_block);
        defer cache.put(cached_buffer);

        @memcpy(cached_buffer.data[0..dev.block_size], buffer[0..dev.block_size]);
        cached_buffer.markDirty();

        // Honor cache policy
        if (dev.cache_policy == .WriteThrough) {
            try cache.sync(cached_buffer);
        }
        return;
    }

    // For multi-block writes, write directly and invalidate cache
    // TODO: Implement write-back for multi-block operations
    try dev.write(start_block, count, buffer);
}

/// Flush all pending writes for a device
pub fn flushDevice(device_name: []const u8) Error!void {
    const dev = findDevice(device_name) orelse return Error.DeviceNotFound;
    try getCache().flushDevice(dev);
}

/// Flush all pending writes for all devices
pub fn flushAll() Error!void {
    try getCache().flushAll();
}

/// Get device information
pub fn getDeviceInfo(device_name: []const u8) ?BlockDevice.DeviceInfo {
    const dev = findDevice(device_name) orelse return null;
    if (dev.ops.get_info) |get_info_fn| {
        return get_info_fn(dev);
    }
    return null;
}

// === UTILITY FUNCTIONS ===

/// Format a block device size for display
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

/// Print device statistics
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

// === TEST INTERFACE ===

/// Run all block device tests
pub fn runTests() !void {
    if (!initialized) {
        logger.err("Block device subsystem not initialized", .{});
        return error.NotInitialized;
    }

    try block_device_test.runAllTests();
}

// === EXAMPLE USAGE ===

pub fn exampleUsage() !void {
    // Initialize the block device subsystem
    try init();
    defer deinit();

    // Find a device
    const device_name = "hda";
    const dev = findDevice(device_name) orelse {
        logger.err("Device {s} not found", .{device_name});
        return;
    };

    // Allocate buffers
    const allocator = @import("../memory.zig").smallAlloc.allocator();
    var buffer = try allocator.alloc(u8, dev.block_size);
    defer allocator.free(buffer);

    // Read a block (with caching)
    try readCached(device_name, 0, 1, buffer);
    logger.info("Read block 0 from {s}", .{device_name});

    // Modify and write back
    buffer[0] = 0x42;
    try writeCached(device_name, 0, 1, buffer);
    logger.info("Wrote modified block 0 to {s}", .{device_name});

    // Flush to ensure data is written
    try flushDevice(device_name);
    logger.info("Flushed {s}", .{device_name});

    // Print statistics
    printDeviceStats(device_name);
    getCache().printStats();
}
