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

const max_transfer_sectors = std.math.maxInt(u16);

pub fn performPolling(op: *@import("ide.zig").IDEOperation) types.IDEError!void {
    const sector_size: u32 = 2048;
    var remaining: u32 = op.count;
    var lba: u32 = op.lba;
    var buffer_offset: usize = 0;

    while (remaining > 0) {
        const chunk: u16 = @intCast(@min(remaining, max_transfer_sectors));
        const chunk_bytes = @as(usize, chunk) * sector_size;

        try issueRead10(op.channel, op.position, lba, chunk, op.buffer.read[buffer_offset..][0..chunk_bytes]);

        remaining -= chunk;
        lba += chunk;
        buffer_offset += chunk_bytes;
    }
}

fn issueRead10(
    channel: *const Channel,
    position: Channel.DrivePosition,
    lba: u32,
    count: u16,
    buffer: []u8,
) IDEError!void {
    const base = channel.base;

    // 1. Select the ATAPI device
    cpu.outb(base + constants.ATA.REG_DEVICE, @bitCast(types.DeviceRegister.select(position)));
    cpu.io_wait();

    // 2. Wait for drive readiness
    _ = try common.waitForReady(base, 1000);

    // 3. Prepare for PACKET command (PIO mode, max byte count)
    cpu.outb(base + constants.ATA.REG_FEATURES, 0x00);
    cpu.outb(base + constants.ATA.REG_LBA_MID, 0xFE);
    cpu.outb(base + constants.ATA.REG_LBA_HIGH, 0xFF);

    // 4. Send the PACKET command
    cpu.outb(base + constants.ATA.REG_COMMAND, constants.ATA.CMD_PACKET);

    // 5. Wait for the drive to accept the packet (DRQ set)
    _ = try common.waitForData(base, 1000);

    // 6. Send the SCSI READ(10) Command Packet (12 bytes)
    var packet = std.mem.zeroes(constants.SCSI.Read10);
    packet.opcode = constants.ATAPI.CMD_READ10;
    packet.lba = std.mem.nativeToBig(u32, lba);
    packet.transfer_len = std.mem.nativeToBig(u16, count);

    const packet_bytes = std.mem.asBytes(&packet);
    cpu.outsw_bytes(base + constants.ATA.REG_DATA, packet_bytes);

    // 7. Data Transfer Phase
    var bytes_read: usize = 0;
    const expected_bytes: usize = @as(usize, count) * 2048;

    while (bytes_read < expected_bytes) {
        const status = try common.waitForDataOrCompletion(base, 5000);
        if (!status.drq) break;

        const byte_count_low = cpu.inb(base + constants.ATA.REG_LBA_MID);
        const byte_count_high = cpu.inb(base + constants.ATA.REG_LBA_HIGH);
        const byte_count = (@as(u16, byte_count_high) << 8) | byte_count_low;

        if (byte_count == 0) break;

        const bytes_to_read = @min(byte_count, expected_bytes - bytes_read);

        const full_words = bytes_to_read / 2;
        const has_partial = bytes_to_read % 2 != 0;

        if (bytes_read + full_words * 2 <= buffer.len) {
            const data_slice = buffer[bytes_read..][0 .. full_words * 2];
            cpu.insw_bytes(base + constants.ATA.REG_DATA, data_slice);
        }

        if (has_partial and bytes_read + full_words * 2 < buffer.len) {
            const word = cpu.inw(base + constants.ATA.REG_DATA);
            buffer[bytes_read + full_words * 2] = @truncate(word);
        }

        bytes_read += bytes_to_read;
    }
}

/// Get ATAPI drive capacity (improved version)
fn getCapacity(channel: *const Channel, position: Channel.DrivePosition) !Capacity {
    cpu.outb(channel.base + constants.ATA.REG_DEVICE, @bitCast(types.DeviceRegister.select(position)));
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
    if (status.err) {
        return IDEError.ReadError;
    }

    // Send READ CAPACITY packet
    var packet = std.mem.zeroes(constants.SCSI.ReadCapacity);
    packet.opcode = constants.ATAPI.CMD_READ_CAPACITY;

    // Send packet (6 words)
    const packet_bytes = std.mem.asBytes(&packet);
    cpu.outsw_bytes(channel.base + constants.ATA.REG_DATA, packet_bytes);

    // Wait for data
    _ = try common.waitForData(channel.base, 1000);

    // Read response (8 bytes)
    var response: [8]u8 = undefined;
    cpu.insw_bytes(channel.base + constants.ATA.REG_DATA, &response);

    // Parse response
    const last_lba = std.mem.readInt(u32, response[0..4], .big);

    const block_size = std.mem.readInt(u32, response[4..8], .big);

    return Capacity{ .sectors = last_lba + 1, .sector_size = block_size };
}

/// Parse ATAPI IDENTIFY response
fn parseIdentifyData(channel: *const Channel, position: Channel.DrivePosition) DriveInfo {
    var raw: [256]u16 = undefined;
    cpu.insw(channel.base + constants.ATA.REG_DATA, &raw);

    _ = cpu.inb(channel.base + constants.ATA.REG_STATUS);

    // Extract model string (Words 27-46 of REG_DATA response)
    std.mem.byteSwapAllFields([20]u16, raw[27..47]);
    var model: [40]u8 = .{0} ** 40;
    const trimmed = std.mem.trim(u8, std.mem.asBytes(raw[27..47]), " \x00");
    @memcpy(model[0..trimmed.len], trimmed);

    const removable = (raw[0] & 0x80) != 0;

    logger.debug("identified {s} {s}: {s} (removable: {s})", .{
        @tagName(channel.channel_type),
        @tagName(position),
        std.mem.trim(u8, &model, " \x00"),
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
        .model = model,
        .capacity = capacity,
        .removable = removable,
    };
}

/// Detect ATAPI drive
/// ATAPI drives function differently: they often don't respond to standard ATA IDENTIFY.
/// Instead, we must check for a specific "Signature" in the Cylinder/LBA registers after a soft reset.
pub fn detectDrive(channel: *const Channel, position: Channel.DrivePosition) ?DriveInfo {
    // 1. Select drive
    cpu.outb(channel.base + constants.ATA.REG_DEVICE, @bitCast(types.DeviceRegister.select(position)));
    cpu.io_wait();

    // 2. Send Software Reset (bit 2 of Control Register)
    // This resets the drive logic but keeps the configuration.
    cpu.outb(channel.ctrl, constants.ATA.CTRL_SRST);
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
        if (status.err) return null;

        // 7. Parse identification data (similar structure to ATA IDENTIFY)
        return parseIdentifyData(channel, position);
    }

    return null;
}
