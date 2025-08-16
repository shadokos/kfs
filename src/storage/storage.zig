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
pub const DeviceRegistry = @import("device_registry.zig").DeviceRegistry;
pub const DeviceProviderType = @import("device_registry.zig").DeviceProviderType;

pub const IDEBlockDevice = @import("ide_device.zig").IDEBlockDevice;
pub const RamDisk = @import("brd.zig").RamDisk;

pub const BlockTranslator = @import("translator.zig").BlockTranslator;
pub const createTranslator = @import("translator.zig").createTranslator;

const ide = @import("../drivers/ide/ide.zig");
const device_registry = @import("device_registry.zig");
const allocator = @import("../memory.zig").smallAlloc.allocator();

var device_manager: DeviceManager = undefined;
var buffer_cache: BufferCache = undefined;
var registry: DeviceRegistry = undefined;
var initialized = false;

pub fn init() !void {
    if (initialized) return;

    logger.info("Initializing storage subsystem", .{});
    logger.info("Standard block size: {} bytes", .{STANDARD_BLOCK_SIZE});

    // Initialiser les composants de base
    device_manager = DeviceManager.init();
    buffer_cache = try BufferCache.init();
    registry = DeviceRegistry.init(&device_manager);

    // Initialiser les drivers sous-jacents
    try ide.init();

    // Enregistrer les providers de dispositifs
    try registerProviders();

    // Découvrir automatiquement tous les dispositifs
    try registry.discoverAll();

    // Créer quelques RAM disks par défaut pour les tests (optionnel)
    try createDefaultRamDisks();

    registry.listDevices();

    initialized = true;
    logger.info("Storage subsystem initialized", .{});
}

pub fn deinit() void {
    if (!initialized) return;

    logger.info("Shutting down storage subsystem", .{});

    flushAll() catch |err| {
        logger.err("Failed to flush cache: {}", .{err});
    };

    registry.deinit();
    ide.deinit();
    buffer_cache.deinit();
    device_manager.deinit();

    initialized = false;
}

fn registerProviders() !void {
    logger.info("Registering device providers", .{});

    // Provider IDE pour auto-découverte
    const ide_provider = try device_registry.createIDEProvider();
    try registry.registerProvider(ide_provider);

    // Provider RAM pour création manuelle
    const ram_provider = try device_registry.createRAMProvider();
    try registry.registerProvider(ram_provider);

    logger.info("Device providers registered", .{});
}

fn createDefaultRamDisks() !void {
    // Créer quelques RAM disks de démonstration
    logger.info("Creating default RAM disks", .{});

    // RAM disk standard (512-byte blocks)
    _ = registry.createRamDisk("ram0", 16, 512) catch |err| {
        logger.warn("Failed to create ram0: {}", .{err});
    };

    // RAM disk simulant un CD-ROM (2048-byte blocks)
    _ = registry.createRamDisk("cdram", 8, 2048) catch |err| {
        logger.warn("Failed to create cdram: {}", .{err});
    };

    // RAM disk moderne (4096-byte blocks)
    _ = registry.createRamDisk("ram4k", 4, 4096) catch |err| {
        logger.warn("Failed to create ram4k: {}", .{err});
    };
}

// API publique simplifiée

pub fn getManager() *DeviceManager {
    return &device_manager;
}

pub fn getRegistry() *DeviceRegistry {
    return &registry;
}

pub fn getCache() *BufferCache {
    return &buffer_cache;
}

pub fn findDevice(name: []const u8) ?*BlockDevice {
    return device_manager.find(name);
}

/// Créer un nouveau RAM disk
pub fn createRamDisk(name: []const u8, size_mb: u32, block_size: u32) !*BlockDevice {
    return registry.createRamDisk(name, size_mb, block_size);
}

/// Supprimer un dispositif (seulement les virtuels)
pub fn removeDevice(device_name: []const u8) !void {
    return registry.removeDevice(device_name);
}

/// Lister tous les dispositifs avec leurs détails
pub fn listAllDevices() void {
    registry.listDevices();
}

// Fonctions I/O (inchangées)

pub fn readCached(
    device_name: []const u8,
    start_block: u32,
    count: u32,
    buffer: []u8,
) BlockError!void {
    const dev = findDevice(device_name) orelse return BlockError.DeviceNotFound;

    if (dev.cache_policy != .NoCache) {
        if (buffer.len < count * STANDARD_BLOCK_SIZE) {
            return BlockError.BufferTooSmall;
        }

        if (count == 1) {
            const cached_buffer = try buffer_cache.get(dev, start_block);
            defer buffer_cache.put(cached_buffer);

            @memcpy(buffer[0..STANDARD_BLOCK_SIZE], cached_buffer.data[0..STANDARD_BLOCK_SIZE]);
            return;
        }
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

    logger.info("Physical blocks: {} x {} bytes", .{ dev.getPhysicalBlockCount(), dev.getPhysicalBlockSize() });
    logger.info("Translation ratio: {}:1", .{dev.getPhysicalBlockSize() / STANDARD_BLOCK_SIZE});
    logger.info("Translator type: {s}", .{
        if (dev.getPhysicalBlockSize() == STANDARD_BLOCK_SIZE) "Direct (1:1)" else "Scaled (N:1)",
    });

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
