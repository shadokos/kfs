// src/storage/ide_device.zig
// Adaptateur simplifié IDE vers BlockDevice

const std = @import("std");
const ide = @import("../../drivers/ide/ide.zig");
const BlockDevice = @import("../../storage/block/block_device.zig").BlockDevice;
const BlockError = @import("../../storage/block/block_device.zig").BlockError;
const DeviceType = @import("../../storage/block/block_device.zig").DeviceType;
const Features = @import("../../storage/block/block_device.zig").Features;
const CachePolicy = @import("../../storage/block/block_device.zig").CachePolicy;
const DeviceInfo = @import("../../storage/block/block_device.zig").DeviceInfo;
const Operations = @import("../../storage/block/block_device.zig").Operations;
const STANDARD_BLOCK_SIZE = @import("../../storage/block/block_device.zig").STANDARD_BLOCK_SIZE;
const createTranslator = @import("../../storage/block/translator.zig").createTranslator;
const logger = std.log.scoped(.ide_block);

const allocator = @import("../../memory.zig").bigAlloc.allocator();

pub const BlockIDE = struct {
    base: BlockDevice,
    drive: *ide.IDEDrive, // Référence directe vers le drive IDE

    const ide_ops = Operations{
        .physical_io = idePhysicalIO,
        .flush = ideFlush,
        .trim = null,
        .get_info = ideGetInfo,
        .media_changed = ideMediaChanged,
        .revalidate = ideRevalidate,
    };

    const Self = @This();

    /// Créer un adaptateur BlockDevice pour un drive IDE
    pub fn create(drive_index: usize) !*Self {
        const drive = ide.getDrive(drive_index) orelse return error.InvalidDrive;

        const device = try allocator.create(Self);
        errdefer allocator.destroy(device);

        // Générer le nom du dispositif
        const device_name = try generateDeviceName(drive);

        // Déterminer le type de dispositif
        const device_type: DeviceType = switch (drive.drive_type) {
            .ATA => .HardDisk,
            .ATAPI => .CDROM,
            else => .Unknown,
        };

        // Configurer les fonctionnalités
        const features = Features{
            .readable = true,
            .writable = drive.drive_type == .ATA,
            .removable = drive.removable,
            .supports_flush = drive.drive_type == .ATA,
            .supports_trim = false,
            .supports_barriers = false,
        };

        // Politique de cache
        const cache_policy: CachePolicy = if (drive.drive_type == .ATAPI)
            .NoCache // Pas de cache pour les CD-ROM
        else
            .WriteBack;

        // Créer le translator approprié
        const physical_block_size = drive.capacity.sector_size;
        const translator = try createTranslator(physical_block_size);
        errdefer translator.deinit();

        // Calculer les blocs logiques
        const logical_blocks_per_physical = physical_block_size / STANDARD_BLOCK_SIZE;
        const total_logical_blocks = drive.capacity.sectors * logical_blocks_per_physical;

        device.* = .{
            .base = .{
                .name = device_name,
                .device_type = device_type,
                .block_size = STANDARD_BLOCK_SIZE,
                .total_blocks = total_logical_blocks,
                .max_transfer = if (drive.drive_type == .ATA)
                    256 * logical_blocks_per_physical
                else
                    65535 * logical_blocks_per_physical,
                .features = features,
                .ops = &ide_ops,
                .translator = translator,
                .private_data = device,
                .cache_policy = cache_policy,
            },
            .drive = drive,
        };

        logger.info("Created IDE block device {s}: {} logical blocks ({} physical of {} bytes)", .{
            device.base.getName(),
            total_logical_blocks,
            drive.capacity.sectors,
            physical_block_size,
        });

        return device;
    }

    pub fn destroy(self: *Self) void {
        self.base.deinit();
        allocator.destroy(self);
    }

    fn generateDeviceName(drive: *ide.IDEDrive) ![16]u8 {
        var name: [16]u8 = [_]u8{0} ** 16;

        // Compter les drives du même type avant celui-ci
        var type_index: u8 = 0;
        for (ide.getAllDrives()) |other_drive| {
            if (other_drive == drive) break;
            if (other_drive.drive_type == drive.drive_type) {
                type_index += 1;
            }
        }

        // Générer le nom selon le type
        if (drive.drive_type == .ATAPI) {
            const str = try std.fmt.bufPrint(&name, "cd{}", .{type_index});
            name[str.len] = 0;
        } else {
            const letter: u8 = @truncate('a' + type_index);
            const str = try std.fmt.bufPrint(&name, "hd{c}", .{letter});
            name[str.len] = 0;
        }

        return name;
    }

    /// Fonction d'I/O physique
    fn idePhysicalIO(
        context: *anyopaque,
        physical_block: u32,
        count: u32,
        buffer: []u8,
        is_write: bool,
    ) BlockError!void {
        const block_device: *BlockDevice = @ptrCast(@alignCast(context));
        const self: *Self = @fieldParentPtr("base", block_device);

        // Calculer la taille attendue
        const expected_size = count * self.base.translator.physical_block_size;
        if (buffer.len < expected_size) {
            return BlockError.BufferTooSmall;
        }

        // Effectuer l'opération via le drive IDE
        if (is_write) {
            self.drive.write(physical_block, @truncate(count), buffer[0..expected_size]) catch |err| {
                self.drive.stats.errors += 1;
                return mapIDEError(err);
            };
        } else {
            self.drive.read(physical_block, @truncate(count), buffer[0..expected_size]) catch |err| {
                self.drive.stats.errors += 1;
                return mapIDEError(err);
            };
        }
    }

    fn ideFlush(dev: *BlockDevice) BlockError!void {
        const self: *Self = @fieldParentPtr("base", dev);

        if (self.drive.drive_type != .ATA) {
            return; // Pas de flush pour ATAPI
        }

        // TODO: Implémenter la commande flush cache IDE
        logger.debug("IDE flush for {s}", .{dev.getName()});
    }

    fn ideGetInfo(dev: *BlockDevice) DeviceInfo {
        const self: *Self = @fieldParentPtr("base", dev);

        const model_len = blk: {
            for (self.drive.model, 0..) |c, idx| {
                if (c == 0) break :blk idx;
            }
            break :blk self.drive.model.len;
        };

        return .{
            .vendor = "Generic",
            .model = self.drive.model[0..model_len],
            .serial = "N/A",
            .firmware_version = "1.0",
            .supports_dma = false,
            .current_speed = 0,
            .physical_block_size = self.drive.capacity.sector_size,
        };
    }

    fn ideMediaChanged(dev: *BlockDevice) bool {
        const self: *Self = @fieldParentPtr("base", dev);

        if (!self.drive.removable) {
            return false;
        }

        // TODO: Implémenter la détection de changement de média
        return false;
    }

    fn ideRevalidate(dev: *BlockDevice) BlockError!void {
        const self: *Self = @fieldParentPtr("base", dev);

        // TODO: Re-interroger le drive pour mettre à jour les infos
        logger.debug("Revalidating {s}", .{dev.getName()});

        // Pour l'instant, on ne fait rien de spécial
        _ = self;
    }

    fn mapIDEError(err: ide.IDEError) BlockError {
        return switch (err) {
            ide.IDEError.InvalidDrive => BlockError.DeviceNotFound,
            ide.IDEError.BufferTooSmall => BlockError.BufferTooSmall,
            ide.IDEError.OutOfBounds => BlockError.OutOfBounds,
            ide.IDEError.Timeout => BlockError.IoError,
            ide.IDEError.NoMedia => BlockError.MediaNotPresent,
            ide.IDEError.NotSupported => BlockError.NotSupported,
            ide.IDEError.MediaChanged => BlockError.MediaNotPresent,
            else => BlockError.IoError,
        };
    }
};
