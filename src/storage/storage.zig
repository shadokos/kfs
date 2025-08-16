// src/storage/storage.zig
// Module principal du système de stockage unifié

const std = @import("std");
const logger = std.log.scoped(.storage);

// Exports publics
pub const BlockDevice = @import("block/block_device.zig").BlockDevice;
pub const BlockError = @import("block/block_device.zig").BlockError;
pub const DeviceType = @import("block/block_device.zig").DeviceType;
pub const Features = @import("block/block_device.zig").Features;
pub const CachePolicy = @import("block/block_device.zig").CachePolicy;
pub const DeviceInfo = @import("block/block_device.zig").DeviceInfo;
pub const STANDARD_BLOCK_SIZE = @import("block/block_device.zig").STANDARD_BLOCK_SIZE;

pub const BufferCache = @import("block/buffer_cache.zig").BufferCache;
pub const Buffer = @import("block/buffer_cache.zig").Buffer;

pub const DeviceManager = @import("block/device_manager.zig").DeviceManager;
pub const DeviceSource = @import("block/device_manager.zig").DeviceSource;

pub const BlockIDE = @import("../devices/block_ide/device.zig").BlockIDE;
// pub const BlockRamDisk = @import("../devices/block_ram_disk/device.zig").BlockRamDisk;

pub const BlockTranslator = @import("block/translator.zig").BlockTranslator;
pub const createTranslator = @import("block/translator.zig").createTranslator;

const ide = @import("../drivers/ide/ide.zig");
const allocator = @import("../memory.zig").smallAlloc.allocator();

// Variables globales
var device_manager: DeviceManager = undefined;
var buffer_cache: BufferCache = undefined;
var initialized = false;

/// Initialiser le sous-système de stockage
pub fn init() !void {
    if (initialized) return;

    logger.info("Initializing storage subsystem", .{});
    logger.info("Standard block size: {} bytes", .{STANDARD_BLOCK_SIZE});

    // Initialiser les composants
    device_manager = DeviceManager.init();
    buffer_cache = try BufferCache.init();

    // IMPORTANT: Initialiser le driver IDE AVANT d'enregistrer les providers
    logger.info("Initializing IDE driver...", .{});
    try ide.init();
    const ide_count = ide.getDriveCount();
    logger.info("IDE driver initialized with {} drives", .{ide_count});

    // Si on a des drives IDE, les enregistrer directement
    // (contournement temporaire du problème de provider)
    if (ide_count > 0) {
        logger.info("Registering IDE devices manually...", .{});

        for (0..ide_count) |i| {
            const ide_device = BlockIDE.create(i) catch |err| {
                logger.err("Failed to create IDE device {}: {}", .{ i, err });
                continue;
            };

            device_manager.registerDevice(&ide_device.base, .IDE, true, null) catch |err| {
                logger.err("Failed to register IDE device: {}", .{err});
                ide_device.destroy();
                continue;
            };

            logger.info("Registered IDE device: {s}", .{ide_device.base.getName()});
        }
    }

    // Enregistrer les providers pour les futurs devices
    try registerProviders();

    // Pour les autres types de devices (pas IDE), utiliser la découverte auto
    // Note: on skip IDE car on l'a déjà fait manuellement
    // TODO: Fix le provider IDE pour que ça marche automatiquement

    // Créer des RAM disks de test (optionnel)
    try createDefaultRamDisks();

    // Afficher l'état initial
    device_manager.list();

    initialized = true;
    logger.info("Storage subsystem initialized successfully", .{});
}

/// Nettoyer le sous-système de stockage
pub fn deinit() void {
    if (!initialized) return;

    logger.info("Shutting down storage subsystem", .{});

    // Vider le cache
    flushAll() catch |err| {
        logger.err("Failed to flush cache: {}", .{err});
    };

    // Nettoyer les composants
    device_manager.deinit();
    buffer_cache.deinit();
    ide.deinit();

    initialized = false;
}

/// Enregistrer les providers de dispositifs
fn registerProviders() !void {
    logger.info("Registering device providers", .{});

    // Provider IDE
    const IDEProvider = @import("../devices/block_ide/provider.zig").IDEProvider;
    const ide_provider = try IDEProvider.create();
    try device_manager.registerProvider(.IDE, &ide_provider.base);

    // Provider RAM
    const RAMProvider = @import("../devices/block_ram_disk/provider.zig").RAMProvider;
    const ram_provider = try RAMProvider.create();
    try device_manager.registerProvider(.RAM, &ram_provider.base);

    logger.info("Device providers registered", .{});
}

/// Créer des RAM disks par défaut pour les tests
fn createDefaultRamDisks() !void {
    logger.info("Creating default RAM disks", .{});

    // RAM disk standard (512-byte blocks)
    _ = device_manager.createDevice(.RAM, "ram0:16:512") catch |err| {
        logger.warn("Failed to create ram0: {}", .{err});
    };

    // RAM disk simulant un CD-ROM (2048-byte blocks)
    _ = device_manager.createDevice(.RAM, "cdram:8:2048") catch |err| {
        logger.warn("Failed to create cdram: {}", .{err});
    };

    // RAM disk moderne (4096-byte blocks)
    _ = device_manager.createDevice(.RAM, "ram4k:4:4096") catch |err| {
        logger.warn("Failed to create ram4k: {}", .{err});
    };
}

// === API publique simplifiée ===

/// Obtenir le gestionnaire de dispositifs
pub fn getManager() *DeviceManager {
    return &device_manager;
}

/// Obtenir le cache de buffers
pub fn getCache() *BufferCache {
    return &buffer_cache;
}

/// Trouver un dispositif par nom
pub fn findDevice(name: []const u8) ?*BlockDevice {
    return device_manager.find(name);
}

/// Créer un RAM disk
pub fn createRamDisk(name: []const u8, size_mb: u32, block_size: u32) !*BlockDevice {
    const params = try std.fmt.allocPrint(allocator, "{s}:{d}:{d}", .{ name, size_mb, block_size });
    defer allocator.free(params);

    return device_manager.createDevice(.RAM, params);
}

/// Supprimer un dispositif (seulement les virtuels)
pub fn removeDevice(device_name: []const u8) !void {
    return device_manager.removeDevice(device_name);
}

/// Lister tous les dispositifs
pub fn listAllDevices() void {
    device_manager.list();
}

/// Lecture avec cache
pub fn readCached(
    device_name: []const u8,
    start_block: u32,
    count: u32,
    buffer: []u8,
) BlockError!void {
    const dev = findDevice(device_name) orelse return BlockError.DeviceNotFound;

    if (dev.cache_policy != .NoCache and count == 1) {
        const cached_buffer = try buffer_cache.get(dev, start_block);
        defer buffer_cache.put(cached_buffer);

        @memcpy(buffer[0..STANDARD_BLOCK_SIZE], cached_buffer.data[0..STANDARD_BLOCK_SIZE]);
        return;
    }

    try dev.read(start_block, count, buffer);
}

/// Écriture avec cache
pub fn writeCached(
    device_name: []const u8,
    start_block: u32,
    count: u32,
    buffer: []const u8,
) BlockError!void {
    const dev = findDevice(device_name) orelse return BlockError.DeviceNotFound;

    if (dev.cache_policy != .NoCache and count == 1) {
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

/// Vider le cache d'un dispositif
pub fn flushDevice(device_name: []const u8) BlockError!void {
    const dev = findDevice(device_name) orelse return BlockError.DeviceNotFound;
    try buffer_cache.flushDevice(dev);
}

/// Vider tous les caches
pub fn flushAll() BlockError!void {
    try buffer_cache.flushAll();
}

/// Obtenir les informations d'un dispositif
pub fn getDeviceInfo(device_name: []const u8) ?DeviceInfo {
    const dev = findDevice(device_name) orelse return null;
    return dev.getInfo();
}

/// Formater une taille en octets pour l'affichage
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

/// Afficher les statistiques d'un dispositif
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
    logger.info("Physical blocks: {} x {} bytes", .{
        dev.getPhysicalBlockCount(),
        dev.getPhysicalBlockSize(),
    });
    logger.info("Translation ratio: {}:1", .{
        dev.getPhysicalBlockSize() / STANDARD_BLOCK_SIZE,
    });

    logger.info("Features:", .{});
    logger.info("  Readable: {}", .{dev.features.readable});
    logger.info("  Writable: {}", .{dev.features.writable});
    logger.info("  Removable: {}", .{dev.features.removable});

    logger.info("Statistics:", .{});
    logger.info("  Reads: {} ({} blocks)", .{
        dev.stats.reads_completed,
        dev.stats.blocks_read,
    });
    logger.info("  Writes: {} ({} blocks)", .{
        dev.stats.writes_completed,
        dev.stats.blocks_written,
    });
    logger.info("  Errors: {}", .{dev.stats.errors});

    if (getDeviceInfo(device_name)) |info| {
        logger.info("Device Info:", .{});
        logger.info("  Vendor: {s}", .{info.vendor});
        logger.info("  Model: {s}", .{info.model});
        logger.info("  Firmware: {s}", .{info.firmware_version});
        logger.info("  Physical block size: {} bytes", .{info.physical_block_size});
    }
}

/// Obtenir les statistiques globales
pub fn getGlobalStats() void {
    const stats = device_manager.getGlobalStats();

    logger.info("=== Global Storage Statistics ===", .{});
    logger.info("Total reads: {}", .{stats.total_reads});
    logger.info("Total writes: {}", .{stats.total_writes});
    logger.info("Total errors: {}", .{stats.total_errors});
    logger.info("Total capacity: {} MB", .{stats.total_capacity_mb});

    buffer_cache.printStats();
}
