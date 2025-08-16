// src/drivers/ide/ide.zig
// Interface simplifiée pour le driver IDE

const std = @import("std");
const logger = std.log.scoped(.ide_driver);
const allocator = @import("../../memory.zig").smallAlloc.allocator();

const discovery = @import("discovery.zig");
const ata = @import("ata.zig");
const atapi = @import("atapi.zig");
const common = @import("common.zig");

pub const constants = @import("constants.zig");
pub const types = @import("types.zig");
pub const Channel = @import("channel.zig");

pub const IDEError = types.IDEError;
pub const DriveType = types.DriveType;
pub const Capacity = types.Capacity;
pub const Buffer = types.Buffer;

/// Structure unifiée pour un drive IDE
pub const IDEDrive = struct {
    /// Index unique du drive (0-3 typiquement)
    index: u8,

    /// Type de drive (ATA ou ATAPI)
    drive_type: DriveType,

    /// Position sur le canal (Master ou Slave)
    position: Channel.DrivePosition,

    /// Référence vers le canal IDE
    channel: *Channel,

    /// Modèle du drive
    model: [41]u8,

    /// Capacité du drive
    capacity: Capacity,

    /// Drive amovible ?
    removable: bool,

    /// Statistiques d'utilisation
    stats: DriveStats = .{},

    pub const DriveStats = struct {
        operations: u64 = 0,
        errors: u64 = 0,
        bytes_transferred: u64 = 0,
    };

    const Self = @This();

    /// Effectuer une opération de lecture
    pub fn read(self: *Self, lba: u32, count: u16, buffer: []u8) IDEError!void {
        const op = IDEOperation{
            .drive = self,
            .lba = lba,
            .count = count,
            .buffer = .{ .read = buffer },
            .is_write = false,
        };

        try performOperation(&op);

        self.stats.operations += 1;
        self.stats.bytes_transferred += @as(u64, count) * self.capacity.sector_size;
    }

    /// Effectuer une opération d'écriture
    pub fn write(self: *Self, lba: u32, count: u16, buffer: []const u8) IDEError!void {
        if (self.drive_type != .ATA) {
            return IDEError.NotSupported;
        }

        const op = IDEOperation{
            .drive = self,
            .lba = lba,
            .count = count,
            .buffer = .{ .write = buffer },
            .is_write = true,
        };

        try performOperation(&op);

        self.stats.operations += 1;
        self.stats.bytes_transferred += @as(u64, count) * self.capacity.sector_size;
    }

    /// Obtenir des informations sur le drive
    pub fn getInfo(self: *const Self) DriveInfo {
        return .{
            .model = self.model,
            .capacity = self.capacity,
            .drive_type = self.drive_type,
            .removable = self.removable,
        };
    }

    /// Afficher les informations du drive
    pub fn print(self: *const Self) void {
        const size_mb = (self.capacity.sectors * self.capacity.sector_size) / (1024 * 1024);
        logger.info("Drive {}: {s}", .{ self.index, self.model });
        logger.info("  Type: {s}, Channel: {s}, Position: {s}", .{
            @tagName(self.drive_type),
            @tagName(self.channel.channel_type),
            @tagName(self.position),
        });
        logger.info("  Capacity: {} MB ({} sectors of {} bytes)", .{
            size_mb,
            self.capacity.sectors,
            self.capacity.sector_size,
        });
        logger.info("  Stats: {} ops, {} errors, {} bytes transferred", .{
            self.stats.operations,
            self.stats.errors,
            self.stats.bytes_transferred,
        });
    }
};

/// Informations basiques d'un drive (utilisé uniquement pendant la découverte)
pub const DriveInfo = struct {
    model: [41]u8,
    capacity: Capacity,
    drive_type: DriveType,
    removable: bool,
};

/// Structure pour une opération IDE
pub const IDEOperation = struct {
    drive: *IDEDrive,
    lba: u32,
    count: u16,
    buffer: Buffer,
    is_write: bool,
};

// Variables globales
var channels: std.ArrayList(*Channel) = undefined;
var drives: std.ArrayList(*IDEDrive) = undefined;
var initialized = false;

/// Initialiser le driver IDE
pub fn init() !void {
    if (initialized) return;

    channels = std.ArrayList(*Channel).init(allocator);
    drives = std.ArrayList(*IDEDrive).init(allocator);

    // Découvrir les contrôleurs
    var channel_list = std.ArrayListAligned(Channel, 4).init(allocator);
    defer channel_list.deinit();

    try discovery.discoverControllers(&channel_list);

    // Allouer et stocker les channels
    for (channel_list.items) |channel| {
        const ch = try allocator.create(Channel);
        ch.* = channel;
        try channels.append(ch);
    }

    // Découvrir les drives sur chaque channel
    var drive_index: u8 = 0;
    for (channels.items) |channel| {
        for ([_]Channel.DrivePosition{ .Master, .Slave }) |position| {
            if (try discovery.detectDrive(channel, position)) |info| {
                const drive = try allocator.create(IDEDrive);
                drive.* = .{
                    .index = drive_index,
                    .drive_type = info.drive_type,
                    .position = position,
                    .channel = channel,
                    .model = info.model,
                    .capacity = info.capacity,
                    .removable = info.removable,
                };

                try drives.append(drive);
                drive_index += 1;

                logger.info("Found drive {}: {s} on {s} {s}", .{
                    drive.index,
                    drive.model,
                    @tagName(channel.channel_type),
                    @tagName(position),
                });
            }
        }
    }

    initialized = true;
    logger.info("IDE driver initialized with {} drives", .{drives.items.len});
}

/// Nettoyer le driver IDE
pub fn deinit() void {
    if (!initialized) return;

    for (drives.items) |drive| {
        allocator.destroy(drive);
    }
    drives.deinit();

    for (channels.items) |channel| {
        allocator.destroy(channel);
    }
    channels.deinit();

    initialized = false;
}

/// Obtenir le nombre de drives
pub fn getDriveCount() usize {
    return drives.items.len;
}

/// Obtenir un drive par index
pub fn getDrive(index: usize) ?*IDEDrive {
    if (index >= drives.items.len) return null;
    return drives.items[index];
}

/// Obtenir tous les drives
pub fn getAllDrives() []const *IDEDrive {
    return drives.items;
}

/// Effectuer une opération IDE
fn performOperation(op: *const IDEOperation) IDEError!void {
    const drive = op.drive;
    const channel = drive.channel;

    // Valider l'opération
    if (op.lba > 0xFFFFFFF and drive.drive_type == .ATA) {
        return IDEError.OutOfBounds;
    }

    // Acquérir le mutex du canal
    channel.mutex.acquire();
    defer channel.mutex.release();

    // Effectuer l'opération selon le type de drive
    if (drive.drive_type == .ATA) {
        try performATAOperation(drive, op);
    } else {
        try performATAPIOperation(drive, op);
    }
}

/// Effectuer une opération ATA
fn performATAOperation(drive: *IDEDrive, op: *const IDEOperation) IDEError!void {
    // Utiliser directement les fonctions ATA avec les bonnes infos

    // var ide_op = @import("ide.zig").IDEOperation{
    //     .drive = drive,
    //     .lba = op.lba,
    //     .count = op.count,
    //     .buffer = op.buffer,
    //     .is_write = op.is_write,
    // };

    try ata.performPolling(drive, @constCast(op));
}

/// Effectuer une opération ATAPI
fn performATAPIOperation(drive: *IDEDrive, op: *const IDEOperation) IDEError!void {
    if (op.is_write) {
        return IDEError.NotSupported;
    }

    try atapi.performPolling(drive, @constCast(op));
}

/// Lister tous les drives
pub fn listDrives() void {
    logger.info("=== IDE Drives ===", .{});
    for (drives.items) |drive| {
        drive.print();
    }
}

// API de compatibilité pour la migration progressive

/// Obtenir les infos d'un drive (pour compatibilité)
pub fn getDriveInfo(drive_idx: usize) ?types.DriveInfo {
    const drive = getDrive(drive_idx) orelse return null;

    return .{
        .drive_type = drive.drive_type,
        .channel = drive.channel.channel_type,
        .position = drive.position,
        .model = drive.model,
        .capacity = drive.capacity,
        .removable = drive.removable,
    };
}

// /// Effectuer une opération (pour compatibilité)
// pub fn performOperation(op: *@import("ide.zig").IDEOperation) IDEError!void {
//     const drive = getDrive(op.drive_idx) orelse return IDEError.InvalidDrive;
//
//     if (op.is_write) {
//         const buffer = op.buffer.write;
//         try drive.write(op.lba, op.count, buffer);
//     } else {
//         const buffer = op.buffer.read;
//         try drive.read(op.lba, op.count, buffer);
//     }
// }
