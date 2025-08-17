const std = @import("std");
const logger = std.log.scoped(.blockdev_disk);

const ide = @import("../../../drivers/ide/ide.zig");

const core = @import("../core.zig");
const types = core.types;
const translator = core.translator;

const BlockDevice = core.BlockDevice;
const BlockError = types.BlockError;
const Features = types.Features;
const Operations = types.Operations;
const DriveStats = types.DriveStats;

const STANDARD_BLOCK_SIZE = core.STANDARD_BLOCK_SIZE;

const Channel = @import("../../../drivers/ide/channel.zig");
const DriveInfo = @import("../../../drivers/ide/types.zig").DriveInfo;

const allocator = @import("../../../memory.zig").bigAlloc.allocator();

var created_count: u8 = 0;

base: BlockDevice,

/// Position sur le canal (Master ou Slave)
position: Channel.DrivePosition,

/// Référence vers le canal IDE
channel: *Channel,

/// Modèle du drive
model: [41]u8,

/// Capacité du drive
capacity: ide.Capacity,

/// Statistiques d'utilisation
stats: DriveStats = .{},

const disk_ops = Operations{
    .physical_io = physical_io,
    .flush = flush,
    .trim = null,
    .media_changed = media_changed,
    .revalidate = revalidate,
};

const Self = @This();

/// Créer un adaptateur BlockDevice pour un drive IDE
pub fn create(drive: DriveInfo, channel: *Channel) !*Self {
    const device = try allocator.create(Self);
    errdefer allocator.destroy(device);

    // Générer le nom du dispositif
    const device_name = try generateDeviceName();

    // Créer le translator approprié
    const physical_block_size = drive.capacity.sector_size;
    const _translator = try translator.createTranslator(allocator, physical_block_size);
    errdefer _translator.deinit();

    // Calculer les blocs logiques
    const logical_blocks_per_physical = physical_block_size / STANDARD_BLOCK_SIZE;
    const total_logical_blocks = drive.capacity.sectors * logical_blocks_per_physical;

    device.* = .{
        .base = .{
            .name = device_name,
            .device_type = .HardDisk,
            .block_size = STANDARD_BLOCK_SIZE,
            .total_blocks = total_logical_blocks,
            .max_transfer = 256 * logical_blocks_per_physical,
            .features = Features{
                .readable = true,
                .writable = true,
                .removable = false,
                .flushable = true,
                .trimable = false,
            },
            .ops = &disk_ops,
            .translator = _translator,
            .cache_policy = .WriteBack,
        },
        .channel = channel,
        .capacity = drive.capacity,
        .position = drive.position,
        .model = drive.model,
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

fn generateDeviceName() ![16]u8 {
    var name: [16]u8 = [_]u8{0} ** 16;

    _ = try std.fmt.bufPrint(&name, "hd{c}", .{@as(u8, @truncate('a' + created_count))});

    created_count += 1;

    return name;
}

/// Fonction d'I/O physique
fn physical_io(
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

    switch (is_write) {
        true => try self.write(physical_block, @truncate(count), buffer[0..expected_size]),
        false => try self.read(physical_block, @truncate(count), buffer[0..expected_size]),
    }
}

/// Effectuer une opération de lecture
pub fn read(self: *Self, lba: u32, count: u16, buffer: []u8) BlockError!void {
    const op = ide.IDEOperation{
        .channel = self.channel,
        .position = self.position,
        .lba = lba,
        .count = count,
        .buffer = .{ .read = buffer },
        .is_write = false,
    };

    ide.performOperation(.ATA, &op) catch |err| {
        self.stats.errors += 1;
        return mapIDEError(err);
    };

    self.stats.operations += 1;
    self.stats.bytes_transferred += @as(u64, count) * self.capacity.sector_size;
}

/// Effectuer une opération d'écriture
pub fn write(self: *Self, lba: u32, count: u16, buffer: []const u8) BlockError!void {
    const op = ide.IDEOperation{
        .channel = self.channel,
        .position = self.position,
        .lba = lba,
        .count = count,
        .buffer = .{ .write = buffer },
        .is_write = true,
    };

    ide.performOperation(.ATA, &op) catch |err| {
        self.stats.errors += 1;
        return mapIDEError(err);
    };

    self.stats.operations += 1;
    self.stats.bytes_transferred += @as(u64, count) * self.capacity.sector_size;
}

fn flush(_: *BlockDevice) BlockError!void {
    // TODO: Implements the flush cache command for hard disk
    logger.warn("flush not implemented yet", .{});
    return error.NotSupported;
}

fn media_changed(_: *BlockDevice) bool {
    return false;
}

fn revalidate(dev: *BlockDevice) BlockError!void {
    logger.warn("{s}: revalidate not implemented", .{dev.getName()});
    return error.NotSupported;
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
