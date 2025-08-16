// src/storage/brd.zig
// Exemple d'implémentation d'un RAM disk utilisant le nouveau système de translation

const std = @import("std");
const BlockDevice = @import("block_device.zig").BlockDevice;
const BlockError = @import("block_device.zig").BlockError;
const DeviceType = @import("block_device.zig").DeviceType;
const Features = @import("block_device.zig").Features;
const CachePolicy = @import("block_device.zig").CachePolicy;
const DeviceInfo = @import("block_device.zig").DeviceInfo;
const Operations = @import("block_device.zig").Operations;
const STANDARD_BLOCK_SIZE = @import("block_device.zig").STANDARD_BLOCK_SIZE;
const createTranslator = @import("translator.zig").createTranslator;
const logger = std.log.scoped(.ram_disk);

const allocator = @import("../memory.zig").bigAlloc.allocator();

pub const RamDisk = struct {
    base: BlockDevice,
    storage: []u8,
    physical_block_size: u32,

    const ram_ops = Operations{
        .physical_io = ramPhysicalIO,
        .flush = ramFlush,
        .trim = ramTrim,
        .get_info = ramGetInfo,
        .media_changed = null,
        .revalidate = null,
    };

    const Self = @This();

    /// Créer un RAM disk avec la taille de bloc physique spécifiée
    pub fn create(
        name: []const u8,
        size_mb: u32,
        physical_block_size: u32,
    ) !*Self {
        // Valider la taille de bloc physique
        if (physical_block_size < STANDARD_BLOCK_SIZE or
            physical_block_size % STANDARD_BLOCK_SIZE != 0)
        {
            return BlockError.InvalidOperation;
        }

        const total_size = size_mb * 1024 * 1024;
        const physical_blocks = total_size / physical_block_size;
        const logical_blocks_per_physical = physical_block_size / STANDARD_BLOCK_SIZE;
        const total_logical_blocks = physical_blocks * logical_blocks_per_physical;

        // Allouer le stockage
        const storage = try allocator.alignedAlloc(u8, 16, total_size);
        errdefer allocator.free(storage);

        // Initialiser à zéro
        @memset(storage, 0);

        // Créer le translator approprié
        const translator = try createTranslator(physical_block_size);
        errdefer translator.deinit();

        // Créer l'instance
        const ramdisk = try allocator.create(Self);
        errdefer allocator.destroy(ramdisk);

        // Générer le nom du dispositif
        var device_name: [16]u8 = [_]u8{0} ** 16;
        const name_len = @min(name.len, 15);
        @memcpy(device_name[0..name_len], name[0..name_len]);

        ramdisk.* = .{
            .base = .{
                .name = device_name,
                .device_type = .RamDisk,
                .block_size = STANDARD_BLOCK_SIZE,
                .total_blocks = total_logical_blocks,
                .max_transfer = 65535, // Pas de limite pratique pour la RAM
                .features = .{
                    .readable = true,
                    .writable = true,
                    .removable = false,
                    .supports_flush = true,
                    .supports_trim = true,
                    .supports_barriers = false,
                },
                .ops = &ram_ops,
                .translator = translator,
                .private_data = ramdisk,
                .cache_policy = .NoCache, // Pas besoin de cache pour la RAM
            },
            .storage = storage,
            .physical_block_size = physical_block_size,
        };

        logger.info("Created RAM disk {s}: {} MB ({} logical blocks, {} physical blocks)", .{
            ramdisk.base.getName(),
            size_mb,
            total_logical_blocks,
            physical_blocks,
        });

        logger.info("  Physical block size: {} bytes", .{physical_block_size});
        logger.info("  Translation ratio: {}:1", .{physical_block_size / STANDARD_BLOCK_SIZE});

        return ramdisk;
    }

    pub fn destroy(self: *Self) void {
        allocator.free(self.storage);
        self.base.deinit(); // Nettoie le translator
        allocator.destroy(self);
    }

    /// Fonction d'I/O physique - c'est ici que la magie opère
    fn ramPhysicalIO(
        context: *anyopaque,
        physical_block: u32,
        count: u32,
        buffer: []u8,
        is_write: bool,
    ) BlockError!void {
        const block_device: *BlockDevice = @ptrCast(@alignCast(context));
        const self: *Self = @fieldParentPtr("base", block_device);

        // Calculer les offsets
        const offset = physical_block * self.physical_block_size;
        const size = count * self.physical_block_size;

        // Vérifier les limites
        if (offset + size > self.storage.len) {
            return BlockError.OutOfBounds;
        }

        if (buffer.len < size) {
            return BlockError.BufferTooSmall;
        }

        // Effectuer l'opération
        if (is_write) {
            @memcpy(self.storage[offset .. offset + size], buffer[0..size]);
        } else {
            @memcpy(buffer[0..size], self.storage[offset .. offset + size]);
        }
    }

    fn ramFlush(dev: *BlockDevice) BlockError!void {
        _ = dev;
        // Rien à faire pour un RAM disk
        logger.debug("RAM flush (no-op)", .{});
    }

    fn ramTrim(dev: *BlockDevice, start_block: u32, count: u32) BlockError!void {
        const self: *Self = @fieldParentPtr("base", dev);

        // Convertir en adresses physiques
        const physical_start = self.base.translator.vtable.logicalToPhysical(
            self.base.translator.context,
            start_block,
        );
        const range = self.base.translator.vtable.calculatePhysicalRange(
            self.base.translator.context,
            start_block,
            count,
        );

        // Remettre à zéro les zones TRIM
        const offset = physical_start * self.physical_block_size;
        const size = range.physical_count * self.physical_block_size;

        if (offset + size <= self.storage.len) {
            @memset(self.storage[offset .. offset + size], 0);
            logger.debug("RAM trim: {} logical blocks ({} physical) at {}", .{
                count,
                range.physical_count,
                start_block,
            });
        }
    }

    fn ramGetInfo(dev: *BlockDevice) DeviceInfo {
        const self: *Self = @fieldParentPtr("base", dev);

        return .{
            .vendor = "Internal",
            .model = "RAM Disk",
            .serial = "RAM-001",
            .firmware_version = "1.0",
            .supports_dma = false,
            .current_speed = 0,
            .physical_block_size = self.physical_block_size,
        };
    }
};

// Fonctions utilitaires pour créer différents types de RAM disks

/// Créer un RAM disk standard (512-byte blocks)
pub fn createStandardRamDisk(name: []const u8, size_mb: u32) !*RamDisk {
    return RamDisk.create(name, size_mb, 512);
}

/// Créer un RAM disk simulant un CD-ROM (2048-byte blocks)
pub fn createCDROMRamDisk(name: []const u8, size_mb: u32) !*RamDisk {
    return RamDisk.create(name, size_mb, 2048);
}

/// Créer un RAM disk avec des blocs de 4K (futur standard)
pub fn createModernRamDisk(name: []const u8, size_mb: u32) !*RamDisk {
    return RamDisk.create(name, size_mb, 4096);
}

// Tests pour démontrer l'utilisation
pub fn runRamDiskTests() !void {
    logger.info("=== RAM Disk Translation Tests ===", .{});

    // Test avec différentes tailles de blocs
    const test_cases = [_]struct { name: []const u8, block_size: u32 }{
        .{ .name = "ram512", .block_size = 512 },
        .{ .name = "ram2k", .block_size = 2048 },
        .{ .name = "ram4k", .block_size = 4096 },
    };

    for (test_cases) |test_case| {
        logger.info("Testing {} byte blocks:", .{test_case.block_size});

        const ramdisk = try RamDisk.create(test_case.name, 1, test_case.block_size);
        defer ramdisk.destroy();

        // Test basique
        try testRamDiskIO(&ramdisk.base);

        // Test des opérations non-alignées (seulement pour les blocs > 512)
        if (test_case.block_size > 512) {
            try testUnalignedIO(&ramdisk.base);
        }

        logger.info("  ✓ Tests passed for {} byte blocks", .{test_case.block_size});
    }

    logger.info("=== All RAM disk tests passed ===", .{});
}

fn testRamDiskIO(device: *BlockDevice) !void {
    const buffer = try allocator.alloc(u8, STANDARD_BLOCK_SIZE * 8);
    defer allocator.free(buffer);

    // Écrire un motif
    for (buffer, 0..) |*byte, i| {
        byte.* = @truncate(i);
    }

    try device.write(10, 8, buffer);

    // Lire et vérifier
    const read_buffer = try allocator.alloc(u8, STANDARD_BLOCK_SIZE * 8);
    defer allocator.free(read_buffer);

    try device.read(10, 8, read_buffer);

    if (!std.mem.eql(u8, buffer, read_buffer)) {
        return error.VerificationFailed;
    }
}

fn testUnalignedIO(device: *BlockDevice) !void {
    const buffer = try allocator.alloc(u8, STANDARD_BLOCK_SIZE * 3);
    defer allocator.free(buffer);

    // Test d'écriture non-alignée (commence au milieu d'un bloc physique)
    for (buffer) |*byte| byte.* = 0xCC;

    try device.write(13, 3, buffer); // Probablement non-aligné

    const read_buffer = try allocator.alloc(u8, STANDARD_BLOCK_SIZE * 3);
    defer allocator.free(read_buffer);

    try device.read(13, 3, read_buffer);

    if (!std.mem.eql(u8, buffer, read_buffer)) {
        return error.UnalignedVerificationFailed;
    }
}
