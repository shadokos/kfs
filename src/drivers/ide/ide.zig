const std = @import("std");
const logger = std.log.scoped(.ide_driver);
const discovery = @import("discovery.zig");
const ata = @import("ata.zig");
const atapi = @import("atapi.zig");
const common = @import("common.zig");

pub const constants = @import("constants.zig");
pub const Channel = @import("channel.zig");
pub const DriveInfo = @import("types.zig").DriveInfo;
pub const DriveType = @import("types.zig").DriveType;
pub const Capacity = @import("types.zig").Capacity;
pub const IDEError = @import("types.zig").IDEError;
pub const Buffer = @import("types.zig").Buffer;

const allocator = @import("../../memory.zig").smallAlloc.allocator();

var channels: std.ArrayListAligned(Channel, 4) = undefined;
var drives: std.ArrayList(DriveInfo) = undefined;
var initialized = false;

pub const IDEOperation = struct {
    drive_idx: usize,
    lba: u32,
    count: u16,
    buffer: Buffer,
    is_write: bool,
    callback: ?*const fn (result: IDEError!void) void = null,
};

pub fn init() !void {
    if (initialized) return;

    channels = std.ArrayListAligned(Channel, 4).init(allocator);
    drives = std.ArrayList(DriveInfo).init(allocator);

    try discovery.discoverControllers(&channels);
    try discovery.detectDrives(&channels, &drives);

    initialized = true;
    logger.info("IDE driver initialized with {} drives", .{drives.items.len});
}

pub fn deinit() void {
    if (!initialized) return;

    channels.deinit();
    drives.deinit();
    initialized = false;
}

pub fn getDriveCount() usize {
    return drives.items.len;
}

pub fn getDriveInfo(drive_idx: usize) ?DriveInfo {
    if (drive_idx >= drives.items.len) return null;
    return drives.items[drive_idx];
}

pub fn performOperation(op: *IDEOperation) IDEError!void {
    if (op.drive_idx >= drives.items.len) return IDEError.InvalidDrive;

    const drive = &drives.items[op.drive_idx];
    const channel = getChannelForDrive(drive) orelse return IDEError.InvalidDrive;

    if (drive.drive_type == .ATAPI and op.is_write) {
        return IDEError.NotSupported;
    }

    try performPollingOperation(channel, drive, op);

    if (op.callback) |cb| {
        cb({});
    }
}

fn performPollingOperation(channel: *Channel, drive: *DriveInfo, op: *IDEOperation) IDEError!void {
    channel.mutex.acquire();
    defer channel.mutex.release();

    if (drive.drive_type == .ATA) {
        try ata.performPolling(channel, drive, op);
    } else {
        try atapi.performPolling(channel, drive, op);
    }
}

fn getChannelForDrive(drive: *const DriveInfo) ?*Channel {
    for (channels.items) |*ch| {
        if (ch.channel_type == drive.channel) return ch;
    }
    return null;
}
