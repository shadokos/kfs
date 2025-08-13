const std = @import("std");
const cpu = @import("../../cpu.zig");
const logger = std.log.scoped(.atapi);

const constants = @import("constants.zig");
const types = @import("types.zig");
const common = @import("common.zig");
const Channel = @import("channel.zig");
const controller = @import("controller.zig");
const request_manager = @import("request_manager.zig");

// === PUBLIC API ===

/// Send generic ATAPI command with packet data
pub fn sendCommand(
    drive_idx: usize,
    packet: []const u8,
    data_buf: []u8,
    timeout: ?usize,
) types.Error!u16 {
    if (drive_idx >= controller.getDriveCount()) return error.InvalidDrive;
    if (packet.len != constants.ATAPI.PACKET_SIZE) return error.InvalidPacket;

    const drive_info = controller.getDriveInfo(drive_idx).?;
    if (!drive_info.isATAPI()) return error.InvalidDrive;

    var packet_data: [constants.ATAPI.PACKET_SIZE]u8 = undefined;
    @memcpy(&packet_data, packet);

    var request = types.Request{
        .channel = drive_info.channel,
        .drive = drive_info.drive,
        .command = constants.ATA.CMD_PACKET,
        .lba = 0,
        .count = 1,
        .buffer = .{ .read = data_buf },
        .packet_data = packet_data,
        .is_atapi = true,
        .current_sector = 0, // Used to count bytes read
    };

    try request_manager.sendRequest(&request, timeout);
    return @truncate(request.current_sector); // Returns number of bytes read
}

/// Read data from CD-ROM using SCSI READ(10) command
pub fn readCDROM(
    drive_idx: usize,
    lba: u32,
    count: u16,
    buf: []u8,
    timeout: ?usize,
) types.Error!void {
    if (buf.len < @as(usize, count) * 2048) return error.BufferTooSmall;

    // Create SCSI READ(10) packet
    var packet: [constants.ATAPI.PACKET_SIZE]u8 = .{0} ** constants.ATAPI.PACKET_SIZE;
    packet[0] = constants.ATAPI.CMD_READ10;
    packet[2] = @truncate(lba >> 24);
    packet[3] = @truncate(lba >> 16);
    packet[4] = @truncate(lba >> 8);
    packet[5] = @truncate(lba);
    packet[7] = @truncate(count >> 8);
    packet[8] = @truncate(count);

    _ = try sendCommand(drive_idx, &packet, buf, timeout);
}

// === INTERNAL OPERATIONS ===

/// Send ATAPI packet command to hardware
pub fn sendCommandToHardware(channel: *Channel, request: *types.Request) !void {
    // Select ATAPI drive
    const select: u8 = if (request.drive == .Master) 0xA0 else 0xB0;
    cpu.outb(channel.base + constants.ATA.REG_DEVICE, select);
    cpu.io_wait();

    _ = try channel.waitForReady();

    // Configure for PACKET command
    cpu.outb(channel.base + constants.ATA.REG_FEATURES, 0x00); // PIO mode
    cpu.outb(channel.base + constants.ATA.REG_LBA_MID, 0xFE); // Maximum transfer size
    cpu.outb(channel.base + constants.ATA.REG_LBA_HIGH, 0xFF);

    // Clear pending interrupts
    _ = cpu.inb(channel.base + constants.ATA.REG_STATUS);

    // Send PACKET command
    cpu.outb(channel.base + constants.ATA.REG_COMMAND, constants.ATA.CMD_PACKET);

    // Wait for DRQ to send packet data
    const status = try channel.waitForData();
    if (status & constants.ATA.STATUS_ERROR != 0) {
        request.err = parseError(cpu.inb(channel.base + constants.ATA.REG_ERROR_READ));
        return request.err.?;
    }

    // Send ATAPI packet (12 bytes = 6 words)
    if (request.packet_data) |packet| {
        for (0..6) |i| {
            const low = packet[i * 2];
            const high = if (i * 2 + 1 < packet.len) packet[i * 2 + 1] else 0;
            const word: u16 = (@as(u16, high) << 8) | low;
            cpu.outw(channel.base + constants.ATA.REG_DATA, word);
        }
    }
}

/// Handle ATAPI packet command interrupt
pub fn handleInterrupt(channel: *Channel, request: *types.Request) void {
    // Read status register
    const status = cpu.inb(channel.base + constants.ATA.REG_STATUS);

    // Check for errors
    if (status & constants.ATA.STATUS_ERROR != 0) {
        const error_reg = cpu.inb(channel.base + constants.ATA.REG_ERROR_READ);
        logger.err("error: status=0x{X:0>2}, error=0x{X:0>2}", .{ status, error_reg });
        request.err = parseError(error_reg);
        request.completed = true;
        channel.queue.try_unblock();
        return;
    }

    // Data phase
    if (status & constants.ATA.STATUS_DRQ != 0) {
        handleDataPhase(channel, request);
        return;
    }

    // Check for completion
    if ((status & constants.ATA.STATUS_BUSY) == 0) {
        logger.debug("Command completed, total bytes: {}", .{request.current_sector});
        request.completed = true;
        channel.queue.try_unblock();
    }
}

// === PRIVATE FUNCTIONS ===

/// Handle ATAPI data phase
fn handleDataPhase(channel: *Channel, request: *types.Request) void {
    // Read byte count from LBA Mid/High registers
    const byte_count_low = cpu.inb(channel.base + constants.ATA.REG_LBA_MID);
    const byte_count_high = cpu.inb(channel.base + constants.ATA.REG_LBA_HIGH);
    const byte_count = (@as(u16, byte_count_high) << 8) | byte_count_low;

    logger.debug("Data phase: {} bytes available", .{byte_count});

    if (byte_count > 0) {
        const available_space = request.buffer.read.len - request.current_sector;
        const bytes_to_read = @min(byte_count, available_space);

        if (bytes_to_read > 0) {
            // Read data by words (2 bytes)
            const word_count = (bytes_to_read + 1) / 2;
            for (0..word_count) |i| {
                const word = cpu.inw(channel.base + constants.ATA.REG_DATA);
                const offset = request.current_sector + i * 2;

                if (offset < request.buffer.read.len) {
                    request.buffer.read[offset] = @truncate(word);
                }
                if (offset + 1 < request.buffer.read.len) {
                    request.buffer.read[offset + 1] = @truncate(word >> 8);
                }
            }

            request.current_sector += @intCast(bytes_to_read);
            logger.debug("Read {} bytes, total: {}", .{ bytes_to_read, request.current_sector });
        }

        // Discard excess bytes
        if (bytes_to_read < byte_count) {
            const remaining_words = (byte_count - bytes_to_read + 1) / 2;
            for (0..remaining_words) |_| {
                _ = cpu.inw(channel.base + constants.ATA.REG_DATA);
            }
            logger.debug("Discarded {} excess bytes", .{byte_count - bytes_to_read});
        }
    }
}

/// Parse ATAPI error register
fn parseError(error_reg: u8) types.Error {
    return common.parseATAPIError(error_reg);
}
