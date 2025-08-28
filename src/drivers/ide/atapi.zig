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
    // 1. Select the ATAPI device (similar to ATA but with different flags)
    common.selectLBADevice(.ATAPI, op);

    // 2. Wait for drive readiness
    _ = try common.waitForReady(op.channel.base, 1000);

    // 3. Prepare for PACKET command
    // ATAPI uses the host's capabilities. We set features to 0 (no DMA, PIO mode).
    // Specifically for ATAPI, LBA Mid/High registers specify the maximum byte count allowed for the transfer.
    // Here we set it to max (0xFFFE/0xFFFF) to avoid truncation.
    cpu.outb(op.channel.base + constants.ATA.REG_FEATURES, 0x00);
    cpu.outb(op.channel.base + constants.ATA.REG_LBA_MID, 0xFE);
    cpu.outb(op.channel.base + constants.ATA.REG_LBA_HIGH, 0xFF);

    // 4. Send the PACKET command (0xA0)
    // This tells the drive "I'm about to send you a SCSI-like command packet structure"
    cpu.outb(op.channel.base + constants.ATA.REG_COMMAND, constants.ATA.CMD_PACKET);

    // 5. Wait for the drive to accept the packet (DRQ set)
    _ = try common.waitForData(op.channel.base, 1000);

    // 6. Send the SCSI Command Packet (12 bytes)
    // We construct a SCSI READ(10) command manually.
    var packet: [12]u8 = .{0} ** 12;
    packet[0] = constants.ATAPI.CMD_READ10; // Operation Code
    // LBA (Logical Block Address) - Big Endian for SCSI
    packet[2] = @truncate(op.lba >> 24);
    packet[3] = @truncate(op.lba >> 16);
    packet[4] = @truncate(op.lba >> 8);
    packet[5] = @truncate(op.lba);
    // Transfer Length (in blocks) - Big Endian
    packet[7] = @truncate(op.count >> 8);
    packet[8] = @truncate(op.count);

    // Send the 12 bytes of the packet as 6 words (16-bit writes)
    for (0..6) |i| {
        const low = packet[i * 2];
        const high = packet[i * 2 + 1];
        const word: u16 = (@as(u16, high) << 8) | low;
        cpu.outw(op.channel.base + constants.ATA.REG_DATA, word);
    }

    // 7. Data Transfer Phase
    var bytes_read: usize = 0;
    const expected_bytes = @as(usize, op.count) * 2048; // CD-ROM sectors are typically 2048 bytes

    while (bytes_read < expected_bytes) {
        // Wait for IRQ or polling status. DRQ indicates data is ready to be read.
        // If BUSY clears and DRQ is missing, the transfer is over.
        const status = try common.waitForDataOrCompletion(op.channel.base, 5000);
        if ((status & constants.ATA.STATUS_DRQ) == 0) break;

        // Read the actual size of the data chunk available from LBA Mid/High registers
        const byte_count_low = cpu.inb(op.channel.base + constants.ATA.REG_LBA_MID);
        const byte_count_high = cpu.inb(op.channel.base + constants.ATA.REG_LBA_HIGH);
        const byte_count = (@as(u16, byte_count_high) << 8) | byte_count_low;

        if (byte_count == 0) break;

        // Sanity check preventing buffer overflow
        const bytes_to_read = @min(byte_count, expected_bytes - bytes_read);
        const word_count = (bytes_to_read + 1) / 2;

        // Read the chunk data
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
/// ATAPI drives function differently: they often don't respond to standard ATA IDENTIFY.
/// Instead, we must check for a specific "Signature" in the Cylinder/LBA registers after a soft reset.
pub fn detectDrive(channel: *const Channel, position: Channel.DrivePosition) ?DriveInfo {
    // 1. Select drive
    const select: u8 = if (position == .Master) 0xA0 else 0xB0;
    cpu.outb(channel.base + constants.ATA.REG_DEVICE, select);
    cpu.io_wait();

    // 2. Send Software Reset (bit 2 of Control Register)
    // This resets the drive logic but keeps the configuration.
    cpu.outb(channel.ctrl, 0x04);
    cpu.io_wait();
    cpu.outb(channel.ctrl, 0x00); // Clear reset
    cpu.io_wait();

    // 3. Wait until the drive is finished resetting (Ready bit set)
    _ = common.waitForReady(channel.base, 1000) catch return null;

    // 4. Check ATAPI Signature
    // After reset, ATAPI drives place specific values in LBA Mid/High registers.
    // LBA Mid:  0x14
    // LBA High: 0xEB
    const lba_mid = cpu.inb(channel.base + constants.ATA.REG_LBA_MID);
    const lba_high = cpu.inb(channel.base + constants.ATA.REG_LBA_HIGH);

    if (lba_mid == constants.ATAPI.SIGNATURE_MID and lba_high == constants.ATAPI.SIGNATURE_HIGH) {
        // ATAPI signature found!

        // 5. Send IDENTIFY PACKET DEVICE command (0xA1)
        // This is the ATAPI equivalent of IDENTIFY.
        cpu.outb(channel.base + constants.ATA.REG_COMMAND, constants.ATA.CMD_IDENTIFY_PACKET);
        cpu.io_wait();

        // 6. Wait for data
        const status = common.waitForData(channel.base, 1000) catch return null;
        if (status & constants.ATA.STATUS_ERROR != 0) return null;

        // 7. Parse identification data (similar structure to ATA IDENTIFY)
        return parseIdentifyData(channel, position);
    }

    return null;
}
