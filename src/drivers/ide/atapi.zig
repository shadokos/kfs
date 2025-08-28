const std = @import("std");
const cpu = @import("../../cpu.zig");
const ide = @import("ide.zig");
const constants = @import("constants.zig");
const types = @import("types.zig");
const common = @import("common.zig");
const Channel = @import("channel.zig");

const IDEOperation = ide.IDEOperation;
const DriveInfo = types.DriveInfo;
const IDEError = types.IDEError;
const Capacity = types.Capacity;

const logger = std.log.scoped(.ATAPI);

pub fn performPolling(op: *@import("ide.zig").IDEOperation) types.IDEError!void {
    common.selectLBADevice(.ATAPI, op);

    _ = try common.waitForReady(op.channel.base, 1000);

    cpu.outb(op.channel.base + constants.ATA.REG_FEATURES, 0x00);
    cpu.outb(op.channel.base + constants.ATA.REG_LBA_MID, 0xFE);
    cpu.outb(op.channel.base + constants.ATA.REG_LBA_HIGH, 0xFF);

    cpu.outb(op.channel.base + constants.ATA.REG_COMMAND, constants.ATA.CMD_PACKET);

    _ = try common.waitForData(op.channel.base, 1000);

    var packet: [12]u8 = .{0} ** 12;
    packet[0] = constants.ATAPI.CMD_READ10;
    packet[2] = @truncate(op.lba >> 24);
    packet[3] = @truncate(op.lba >> 16);
    packet[4] = @truncate(op.lba >> 8);
    packet[5] = @truncate(op.lba);
    packet[7] = @truncate(op.count >> 8);
    packet[8] = @truncate(op.count);

    for (0..6) |i| {
        const low = packet[i * 2];
        const high = packet[i * 2 + 1];
        const word: u16 = (@as(u16, high) << 8) | low;
        cpu.outw(op.channel.base + constants.ATA.REG_DATA, word);
    }

    var bytes_read: usize = 0;
    const expected_bytes = @as(usize, op.count) * 2048;

    while (bytes_read < expected_bytes) {
        const status = try common.waitForDataOrCompletion(op.channel.base, 5000);
        if ((status & constants.ATA.STATUS_DRQ) == 0) break;

        const byte_count_low = cpu.inb(op.channel.base + constants.ATA.REG_LBA_MID);
        const byte_count_high = cpu.inb(op.channel.base + constants.ATA.REG_LBA_HIGH);
        const byte_count = (@as(u16, byte_count_high) << 8) | byte_count_low;

        if (byte_count == 0) break;

        const bytes_to_read = @min(byte_count, expected_bytes - bytes_read);
        const word_count = (bytes_to_read + 1) / 2;

        for (0..word_count) |i| {
            const word = cpu.inw(op.channel.base + constants.ATA.REG_DATA);
            const offset = bytes_read + i * 2;

            if (offset < op.buffer.read.len) {
                op.buffer.read[offset] = @truncate(word);
            }
            if (offset + 1 < op.buffer.read.len) {
                op.buffer.read[offset + 1] = @truncate(word >> 8);
            }
        }

        bytes_read += bytes_to_read;
    }
}

/// Get ATAPI drive capacity (improved version)
fn getCapacity(channel: *const Channel, position: Channel.DrivePosition) !Capacity {
    const select: u8 = if (position == .Master) 0xA0 else 0xB0;
    cpu.outb(channel.base + constants.ATA.REG_DEVICE, select);
    cpu.io_wait();

    _ = try common.waitForReady(channel.base, 1000);

    // Configure for PACKET command
    cpu.outb(channel.base + constants.ATA.REG_FEATURES, 0x00);
    cpu.outb(channel.base + constants.ATA.REG_LBA_MID, 0x08);
    cpu.outb(channel.base + constants.ATA.REG_LBA_HIGH, 0x00);

    // Send PACKET command
    cpu.outb(channel.base + constants.ATA.REG_COMMAND, constants.ATA.CMD_PACKET);

    // Wait for DRQ
    const status = try common.waitForData(channel.base, 1000);
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
    _ = try common.waitForData(channel.base, 1000);

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

/// Parse ATAPI IDENTIFY response
fn parseIdentifyData(channel: *const Channel, position: Channel.DrivePosition) DriveInfo {
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

    logger.debug("identified {s} {s}: {s} (removable: {s})", .{
        @tagName(channel.channel_type),
        @tagName(position),
        model_arr[0..model_len],
        if (removable) "yes" else "no",
    });

    // Try to get capacity (may fail if no media)
    var capacity = Capacity{ .sectors = 0, .sector_size = 2048 };
    if (getCapacity(channel, position)) |cap| {
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

/// Detect ATAPI drive
pub fn detectDrive(channel: *const Channel, position: Channel.DrivePosition) ?DriveInfo {
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
    _ = common.waitForReady(channel.base, 1000) catch return null;

    // Check ATAPI signature
    const lba_mid = cpu.inb(channel.base + constants.ATA.REG_LBA_MID);
    const lba_high = cpu.inb(channel.base + constants.ATA.REG_LBA_HIGH);

    if (lba_mid == 0x14 and lba_high == 0xEB) {
        // ATAPI signature found
        // logger.debug("ATAPI signature found on {s} {s}", .{ @tagName(channel.channel_type), @tagName(position) });

        // Send IDENTIFY PACKET DEVICE command
        cpu.outb(channel.base + constants.ATA.REG_COMMAND, constants.ATA.CMD_IDENTIFY_PACKET);
        cpu.io_wait();

        const status = common.waitForData(channel.base, 1000) catch return null;
        if (status & constants.ATA.STATUS_ERROR != 0) return null;

        return parseIdentifyData(channel, position);
    }

    return null;
}
