const std = @import("std");
const cpu = @import("../../cpu.zig");
const ide = @import("ide.zig");
const constants = @import("constants.zig");
const types = @import("types.zig");
const common = @import("common.zig");
const Channel = @import("channel.zig");

pub fn performPolling(drive: *ide.IDEDrive, op: *@import("ide.zig").IDEOperation) types.IDEError!void {
    // const select: u8 = if (drive.position == .Master) 0xA0 else 0xB0;
    // cpu.outb(channel.base + constants.ATA.REG_DEVICE, select);
    // common.waitNs(400);
    //

    common.selectLBADevice(drive, drive.channel.base, op.lba);

    _ = try common.waitForReady(drive.channel.base, 1000);

    cpu.outb(drive.channel.base + constants.ATA.REG_FEATURES, 0x00);
    cpu.outb(drive.channel.base + constants.ATA.REG_LBA_MID, 0xFE);
    cpu.outb(drive.channel.base + constants.ATA.REG_LBA_HIGH, 0xFF);

    cpu.outb(drive.channel.base + constants.ATA.REG_COMMAND, constants.ATA.CMD_PACKET);

    _ = try common.waitForData(drive.channel.base, 1000);

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
        cpu.outw(drive.channel.base + constants.ATA.REG_DATA, word);
    }

    var bytes_read: usize = 0;
    const expected_bytes = @as(usize, op.count) * 2048;

    while (bytes_read < expected_bytes) {
        const status = try common.waitForDataOrCompletion(drive.channel.base, 5000);
        if ((status & constants.ATA.STATUS_DRQ) == 0) break;

        const byte_count_low = cpu.inb(drive.channel.base + constants.ATA.REG_LBA_MID);
        const byte_count_high = cpu.inb(drive.channel.base + constants.ATA.REG_LBA_HIGH);
        const byte_count = (@as(u16, byte_count_high) << 8) | byte_count_low;

        if (byte_count == 0) break;

        const bytes_to_read = @min(byte_count, expected_bytes - bytes_read);
        const word_count = (bytes_to_read + 1) / 2;

        for (0..word_count) |i| {
            const word = cpu.inw(drive.channel.base + constants.ATA.REG_DATA);
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

// pub fn sendCommand(channel: *Channel, request: *Channel.Request) types.IDEError!void {
//     // const select: u8 = if (request.drive == .Master) 0xA0 else 0xB0;
//     // cpu.outb(channel.base + constants.ATA.REG_DEVICE, select);
//     // common.waitNs(400);
//
//     common.selectLBADevice(drive: *types.DriveInfo, channel.base, undefined)
//
//     _ = try common.waitForReady(channel.base, 1000);
//
//     cpu.outb(channel.base + constants.ATA.REG_FEATURES, 0x00);
//     cpu.outb(channel.base + constants.ATA.REG_LBA_MID, 0xFE);
//     cpu.outb(channel.base + constants.ATA.REG_LBA_HIGH, 0xFF);
//
//     _ = cpu.inb(channel.base + constants.ATA.REG_STATUS);
//
//     cpu.outb(channel.base + constants.ATA.REG_COMMAND, constants.ATA.CMD_PACKET);
//
//     const status = try common.waitForData(channel.base, 1000);
//     if (status & constants.ATA.STATUS_ERROR != 0) {
//         request.err = common.parseError(channel.base);
//         return request.err.?;
//     }
//
//     var packet: [12]u8 = .{0} ** 12;
//     packet[0] = constants.ATAPI.CMD_READ10;
//     packet[2] = @truncate(request.lba >> 24);
//     packet[3] = @truncate(request.lba >> 16);
//     packet[4] = @truncate(request.lba >> 8);
//     packet[5] = @truncate(request.lba);
//     packet[7] = @truncate(request.count >> 8);
//     packet[8] = @truncate(request.count);
//
//     for (0..6) |i| {
//         const low = packet[i * 2];
//         const high = packet[i * 2 + 1];
//         const word: u16 = (@as(u16, high) << 8) | low;
//         cpu.outw(channel.base + constants.ATA.REG_DATA, word);
//     }
// }
