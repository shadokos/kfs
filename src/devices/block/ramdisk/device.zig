const std = @import("std");
const block_device = @import("../../../storage/block/block_device.zig");
const BlockDevice = block_device.BlockDevice;
const BlockError = block_device.BlockError;
const DeviceType = block_device.DeviceType;
const Features = block_device.Features;
const CachePolicy = block_device.CachePolicy;
const DeviceInfo = block_device.DeviceInfo;
const Operations = block_device.Operations;

const STANDARD_BLOCK_SIZE = block_device.STANDARD_BLOCK_SIZE;
const createTranslator = @import("../../../storage/block/translator.zig").createTranslator;

const logger = std.log.scoped(.blockdev_ram);

const allocator = @import("../../../memory.zig").bigAlloc.allocator();

base: BlockDevice,
storage: []u8,
physical_block_size: u32,

const ram_ops = Operations{
    .physical_io = ramPhysicalIO,
    .flush = ramFlush,
    .trim = ramTrim,
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
                .flushable = true,
                .trimable = true,
            },
            .ops = &ram_ops,
            .translator = translator,
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
    const device: *BlockDevice = @ptrCast(@alignCast(context));
    const self: *Self = @fieldParentPtr("base", device);

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
