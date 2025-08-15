const std = @import("std");
const cpu = @import("../../cpu.zig");
const pci = @import("../pci/pci.zig");
const timer = @import("../../timer.zig");
const logger = std.log.scoped(.ide_discovery);

pub const constants = @import("constants.zig");
pub const Channel = @import("channel.zig");
pub const DriveInfo = @import("types.zig").DriveInfo;
pub const DriveType = @import("types.zig").DriveType;
pub const Capacity = @import("types.zig").Capacity;
pub const IDEError = @import("types.zig").IDEError;

const allocator = @import("../../memory.zig").smallAlloc.allocator();

pub fn discoverControllers(channels: *std.ArrayListAligned(Channel, 4)) !void {
    const ide_controllers = pci.findIDEControllers();

    if (ide_controllers) |controller_list| {
        defer allocator.free(controller_list);

        for (controller_list) |controller| {
            const interface = controller.getIDEInterface() orelse continue;

            var primary_base: u16 = 0x1F0;
            var primary_ctrl: u16 = 0x3F6;
            var secondary_base: u16 = 0x170;
            var secondary_ctrl: u16 = 0x376;

            if (interface.isPCINative()) {
                primary_base = @truncate(controller.bars[0] & 0xFFFC);
                primary_ctrl = @truncate(controller.bars[1] & 0xFFFC);
                secondary_base = @truncate(controller.bars[2] & 0xFFFC);
                secondary_ctrl = @truncate(controller.bars[3] & 0xFFFC);
            }

            if (primary_base != 0) {
                try channels.append(Channel{
                    .base = primary_base,
                    .ctrl = primary_ctrl,
                    .channel_type = .Primary,
                    .irq = if (interface.isPCINative()) controller.irq_line else 14,
                });
            }

            if (secondary_base != 0) {
                try channels.append(Channel{
                    .base = secondary_base,
                    .ctrl = secondary_ctrl,
                    .channel_type = .Secondary,
                    .irq = if (interface.isPCINative()) controller.irq_line else 15,
                });
            }
        }
    }

    if (channels.items.len == 0) {
        try channels.append(Channel{
            .base = 0x1F0,
            .ctrl = 0x3F6,
            .channel_type = .Primary,
            .irq = 14,
        });
        try channels.append(Channel{
            .base = 0x170,
            .ctrl = 0x376,
            .channel_type = .Secondary,
            .irq = 15,
        });
    }
}

pub fn detectDrives(channels: *std.ArrayListAligned(Channel, 4), drives: *std.ArrayList(DriveInfo)) !void {
    for (channels.items) |*channel| {
        for ([_]Channel.DrivePosition{ .Master, .Slave }) |position| {
            if (try detectDrive(channel, position)) |drive_info| {
                try drives.append(drive_info);
            }
        }
    }
}

pub fn detectDrive(channel: *Channel, position: Channel.DrivePosition) !?DriveInfo {
    // First, try ATA detection
    if (try detectATADrive(channel, position)) |drive_info| {
        logger.debug("ATA drive detected on {s} {s}", .{ @tagName(channel.channel_type), @tagName(position) });
        return drive_info;
    }

    // Then try ATAPI detection
    if (try detectATAPIDrive(channel, position)) |drive_info| {
        logger.debug("ATAPI drive detected on {s} {s}", .{ @tagName(channel.channel_type), @tagName(position) });
        return drive_info;
    }

    return null;
}

/// Detect ATA drive
fn detectATADrive(channel: *Channel, position: Channel.DrivePosition) !?DriveInfo {
    // Select drive
    const select: u8 = if (position == .Master) 0xA0 else 0xB0;
    cpu.outb(channel.base + constants.ATA.REG_DEVICE, select);
    cpu.io_wait();

    // Clear status
    _ = cpu.inb(channel.base + constants.ATA.REG_STATUS);

    // Test presence with IDENTIFY command
    cpu.outb(channel.base + constants.ATA.REG_COMMAND, constants.ATA.CMD_IDENTIFY);
    cpu.io_wait();

    var status = cpu.inb(channel.base + constants.ATA.REG_STATUS);
    if (status == 0 or status == 0xFF) {
        return null;
    }

    // Wait for response
    status = waitForData(channel.base, 1000) catch return null;

    if (status & constants.ATA.STATUS_ERROR != 0) {
        return null;
    }

    // Read IDENTIFY data
    return parseATAIdentifyData(channel, position);
}

/// Detect ATAPI drive
fn detectATAPIDrive(channel: *Channel, position: Channel.DrivePosition) !?DriveInfo {
    // Select drive
    const select: u8 = if (position == .Master) 0xA0 else 0xB0;
    cpu.outb(channel.base + constants.ATA.REG_DEVICE, select);
    cpu.io_wait();

    // Software reset
    cpu.outb(channel.ctrl, 0x04);
    cpu.io_wait();
    cpu.outb(channel.ctrl, 0x00);
    cpu.io_wait();

    // Wait for stabilization
    _ = waitForReady(channel.base, 1000) catch return null;

    // Check ATAPI signature
    const lba_mid = cpu.inb(channel.base + constants.ATA.REG_LBA_MID);
    const lba_high = cpu.inb(channel.base + constants.ATA.REG_LBA_HIGH);

    if (lba_mid == 0x14 and lba_high == 0xEB) {
        // ATAPI signature found
        logger.debug("ATAPI signature found on {s} {s}", .{ @tagName(channel.channel_type), @tagName(position) });

        // Send IDENTIFY PACKET DEVICE command
        cpu.outb(channel.base + constants.ATA.REG_COMMAND, constants.ATA.CMD_IDENTIFY_PACKET);
        cpu.io_wait();

        const status = waitForData(channel.base, 1000) catch return null;
        if (status & constants.ATA.STATUS_ERROR != 0) return null;

        return parseATAPIIdentifyData(channel, position);
    }

    return null;
}

/// Parse ATA IDENTIFY response
fn parseATAIdentifyData(channel: *Channel, position: Channel.DrivePosition) DriveInfo {
    var raw: [256]u16 = undefined;
    for (0..256) |i| {
        raw[i] = cpu.inw(channel.base + constants.ATA.REG_DATA);
    }

    _ = cpu.inb(channel.base + constants.ATA.REG_STATUS);

    // Extract model string
    var model_arr: [41]u8 = .{0} ** 41;
    var widx: usize = 27;
    var midx: usize = 0;
    while (widx <= 46) : (widx += 1) {
        const w = raw[widx];
        model_arr[midx] = @truncate(w >> 8);
        model_arr[midx + 1] = @truncate(w & 0xFF);
        midx += 2;
    }

    // Trim trailing spaces
    var model_len: usize = 40;
    while (model_len > 0) : (model_len -= 1) {
        if (model_arr[model_len - 1] != ' ' and model_arr[model_len - 1] != 0) break;
    }
    if (model_len < model_arr.len) model_arr[model_len] = 0;

    // Extract total sectors
    const sec_lo: u32 = raw[60];
    const sec_hi: u32 = raw[61];
    const total: u64 = (@as(u64, sec_hi) << 16) | sec_lo;

    logger.debug("ATA {s} {s}: {s} ({} sectors)", .{
        @tagName(channel.channel_type),
        @tagName(position),
        model_arr[0..model_len],
        total,
    });

    return DriveInfo{
        .drive_type = .ATA,
        .channel = channel.channel_type,
        .position = position,
        .model = model_arr,
        .capacity = Capacity{ .sectors = total, .sector_size = 512 },
        .removable = false,
    };
}

/// Parse ATAPI IDENTIFY response
fn parseATAPIIdentifyData(channel: *Channel, position: Channel.DrivePosition) DriveInfo {
    var raw: [256]u16 = undefined;
    for (0..256) |i| {
        raw[i] = cpu.inw(channel.base + constants.ATA.REG_DATA);
    }

    _ = cpu.inb(channel.base + constants.ATA.REG_STATUS);

    // Extract model string
    var model_arr: [41]u8 = .{0} ** 41;
    var widx: usize = 27;
    var midx: usize = 0;
    while (widx <= 46) : (widx += 1) {
        const w = raw[widx];
        model_arr[midx] = @truncate(w >> 8);
        model_arr[midx + 1] = @truncate(w & 0xFF);
        midx += 2;
    }

    // Trim trailing spaces
    var model_len: usize = 40;
    while (model_len > 0) : (model_len -= 1) {
        if (model_arr[model_len - 1] != ' ' and model_arr[model_len - 1] != 0) break;
    }
    if (model_len < model_arr.len) model_arr[model_len] = 0;

    const removable = (raw[0] & 0x80) != 0;

    logger.debug("ATAPI {s} {s}: {s} (removable: {s})", .{
        @tagName(channel.channel_type),
        @tagName(position),
        model_arr[0..model_len],
        if (removable) "yes" else "no",
    });

    // Try to get capacity (may fail if no media)
    var capacity = Capacity{ .sectors = 0, .sector_size = 2048 };
    if (getATAPICapacityImproved(channel, position)) |cap| {
        capacity = cap;
    } else |err| {
        logger.debug("Could not read ATAPI capacity: {s} (no media?)", .{@errorName(err)});
    }

    return DriveInfo{
        .drive_type = .ATAPI,
        .channel = channel.channel_type,
        .position = position,
        .model = model_arr,
        .capacity = capacity,
        .removable = removable,
    };
}

/// Get ATAPI drive capacity (improved version)
fn getATAPICapacityImproved(channel: *Channel, position: Channel.DrivePosition) !Capacity {
    const select: u8 = if (position == .Master) 0xA0 else 0xB0;
    cpu.outb(channel.base + constants.ATA.REG_DEVICE, select);
    cpu.io_wait();

    _ = try waitForReady(channel.base, 1000);

    // Configure for PACKET command
    cpu.outb(channel.base + constants.ATA.REG_FEATURES, 0x00);
    cpu.outb(channel.base + constants.ATA.REG_LBA_MID, 0x08);
    cpu.outb(channel.base + constants.ATA.REG_LBA_HIGH, 0x00);

    // Send PACKET command
    cpu.outb(channel.base + constants.ATA.REG_COMMAND, constants.ATA.CMD_PACKET);

    // Wait for DRQ
    const status = try waitForData(channel.base, 1000);
    if (status & constants.ATA.STATUS_ERROR != 0) {
        return IDEError.ReadError;
    }

    // Send READ CAPACITY packet
    var packet: [12]u8 = .{0} ** 12;
    packet[0] = constants.ATAPI.CMD_READ_CAPACITY;

    // Send packet (6 words)
    for (0..6) |i| {
        const low = packet[i * 2];
        const high = if (i * 2 + 1 < packet.len) packet[i * 2 + 1] else 0;
        const word: u16 = (@as(u16, high) << 8) | low;
        cpu.outw(channel.base + constants.ATA.REG_DATA, word);
    }

    // Wait for data
    _ = try waitForData(channel.base, 1000);

    // Read response (8 bytes)
    var response: [8]u8 = undefined;
    for (0..4) |i| {
        const word = cpu.inw(channel.base + constants.ATA.REG_DATA);
        response[i * 2] = @truncate(word);
        response[i * 2 + 1] = @truncate(word >> 8);
    }

    // Parse response
    const last_lba = (@as(u32, response[0]) << 24) |
        (@as(u32, response[1]) << 16) |
        (@as(u32, response[2]) << 8) |
        response[3];

    const block_size = (@as(u32, response[4]) << 24) |
        (@as(u32, response[5]) << 16) |
        (@as(u32, response[6]) << 8) |
        response[7];

    return Capacity{ .sectors = last_lba + 1, .sector_size = block_size };
}

// Utility functions needed for discovery
fn waitForReady(base: u16, timeout_ms: usize) IDEError!u8 {
    const deadline = timer.get_time_since_boot() + timeout_ms;

    while (true) {
        const status = cpu.inb(base + constants.ATA.REG_STATUS);
        if ((status & constants.ATA.STATUS_BUSY) == 0) {
            if (status & constants.ATA.STATUS_ERROR != 0) {
                return parseError(base);
            }
            return status;
        }
        if (timer.get_time_since_boot() >= deadline) {
            return IDEError.Timeout;
        }
        cpu.io_wait();
    }
}

fn waitForData(base: u16, timeout_ms: usize) IDEError!u8 {
    const deadline = timer.get_time_since_boot() + timeout_ms;

    while (true) {
        const status = cpu.inb(base + constants.ATA.REG_STATUS);
        if ((status & (constants.ATA.STATUS_BUSY | constants.ATA.STATUS_DRQ)) == constants.ATA.STATUS_DRQ) {
            return status;
        }
        if (timer.get_time_since_boot() >= deadline) {
            return IDEError.Timeout;
        }
        cpu.io_wait();
    }
}

fn parseError(base: u16) IDEError {
    const err = cpu.inb(base + constants.ATA.REG_ERROR_READ);
    if (err & constants.ATA.ERROR_BAD_BLOCK != 0) return IDEError.BadBlock;
    if (err & constants.ATA.ERROR_UNCORRECTABLE != 0) return IDEError.UncorrectableError;
    if (err & constants.ATA.ERROR_MEDIA_CHANGED != 0) return IDEError.MediaChanged;
    if (err & constants.ATA.ERROR_ID_MARK_NOT_FOUND != 0) return IDEError.SectorNotFound;
    if (err & constants.ATA.ERROR_MEDIA_CHANGE_REQ != 0) return IDEError.MediaChangeRequested;
    if (err & constants.ATA.ERROR_CMD_ABORTED != 0) return IDEError.CommandAborted;
    if (err & constants.ATA.ERROR_TRACK0_NOT_FOUND != 0) return IDEError.Track0NotFound;
    if (err & constants.ATA.ERROR_ADDR_MARK_NOT_FOUND != 0) return IDEError.AddressMarkNotFound;
    return IDEError.UnknownError;
}
