// src/drivers/ide/ide.zig
// Interface simplifiée pour le driver IDE

const std = @import("std");
const logger = std.log.scoped(.driver_ide);
const allocator = @import("../../memory.zig").smallAlloc.allocator();

const common = @import("common.zig");

pub const ata = @import("ata.zig");
pub const atapi = @import("atapi.zig");

pub const constants = @import("constants.zig");
pub const types = @import("types.zig");
pub const Channel = @import("channel.zig");

pub const IDEError = types.IDEError;
pub const DriveType = types.DriveType;
pub const Capacity = types.Capacity;
pub const Buffer = types.Buffer;

/// Informations basiques d'un drive (utilisé uniquement pendant la découverte)
pub const DriveInfo = struct {
    model: [41]u8,
    capacity: Capacity,
    drive_type: DriveType,
    removable: bool,
};

/// Structure pour une opération IDE
pub const IDEOperation = struct {
    // drive: *IDEDrive,
    position: Channel.DrivePosition,
    channel: *Channel,
    lba: u32,
    count: u16,
    buffer: Buffer,
    is_write: bool,
};

var initialized = false;

const pci = @import("../pci/pci.zig");
pub var channels: []Channel = undefined;
pub var interfaces: []pci.PCIDevice = undefined;

/// Initialiser le driver IDE
pub fn init() !void {
    if (initialized) return;

    logger.debug("Initializing IDE driver...", .{});

    {
        const list = pci.findIDEControllers(allocator);
        if (list == null or list.?.len == 0) {
            logger.warn("No IDE interface found", .{});
            return;
        }
        interfaces = list.?;

        logger.debug("Found {} IDE interface", .{interfaces.len});
    }

    {
        const list = Channel.get_all_channels(allocator);
        if (list == null or list.?.len == 0) {
            logger.warn("No IDE channels found", .{});
            return;
        }
        channels = list.?;

        logger.debug("Found {} IDE channels", .{channels.len});
    }

    initialized = true;
    logger.info("IDE driver initialized, {} interface(s) found", .{interfaces.len});
}

/// Nettoyer le driver IDE
pub fn deinit() void {
    if (!initialized) return;

    allocator.free(channels);

    allocator.free(interfaces);

    initialized = false;
}

/// Effectuer une opération IDE
pub fn performOperation(drive_type: DriveType, op: *const IDEOperation) IDEError!void {
    // const drive = op.drive;
    const channel = op.channel;

    // Valider l'opération
    if (op.lba > 0xFFFFFFF and drive_type == .ATA) {
        return IDEError.OutOfBounds;
    }

    // Acquérir le mutex du canal
    channel.mutex.acquire();
    defer channel.mutex.release();

    // Effectuer l'opération selon le type de drive
    if (drive_type == .ATA) {
        try ata.performPolling(@constCast(op));
    } else {
        try atapi.performPolling(@constCast(op));
    }
}
