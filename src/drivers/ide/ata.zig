const std = @import("std");
const cpu = @import("../../cpu.zig");
const timer = @import("../../timer.zig");
const constants = @import("constants.zig");
const types = @import("types.zig");
const common = @import("common.zig");
const Channel = @import("channel.zig");

pub fn performPolling(channel: *Channel, drive: *types.DriveInfo, op: *@import("ide.zig").IDEOperation) types.IDEError!void {
    if (op.lba > 0xFFFFFFF) return types.IDEError.OutOfBounds;

    const total_chunks = getTotalChunks(op.count);

    for (0..total_chunks) |chunk_idx| {
        const chunk_info = getChunkInfo(op.count, chunk_idx);
        if (chunk_info.count == 0) break;

        const chunk_lba = op.lba + (chunk_idx * 255);
        const lba32 = @as(u32, @truncate(chunk_lba));

        common.selectLBADevice(drive, channel.base, lba32);

        _ = try common.waitForReady(channel.base, 1000);

        cpu.outb(channel.base + constants.ATA.REG_SEC_COUNT, chunk_info.count);
        cpu.outb(channel.base + constants.ATA.REG_LBA_LOW, @truncate(lba32));
        cpu.outb(channel.base + constants.ATA.REG_LBA_MID, @truncate(lba32 >> 8));
        cpu.outb(channel.base + constants.ATA.REG_LBA_HIGH, @truncate(lba32 >> 16));

        const cmd = if (op.is_write) constants.ATA.CMD_WRITE_SECTORS else constants.ATA.CMD_READ_SECTORS;
        cpu.outb(channel.base + constants.ATA.REG_COMMAND, cmd);

        for (0..chunk_info.count) |i| {
            _ = try common.waitForData(channel.base, 5000);

            const offset = chunk_info.offset + i * 512;
            if (op.is_write) {
                common.writeSectorPIO(channel.base, op.buffer.write[offset .. offset + 512]);
            } else {
                common.readSectorPIO(channel.base, op.buffer.read[offset .. offset + 512]);
            }
        }

        if (op.is_write) {
            _ = try common.waitForReady(channel.base, 1000);
        }
    }
}

fn getChunkInfo(total_count: u16, chunk_index: usize) struct { count: u8, offset: usize } {
    const max_chunk_size: u16 = 255;
    const chunks_before = chunk_index;
    const sectors_before = chunks_before * max_chunk_size;

    if (sectors_before >= total_count) {
        return .{ .count = 0, .offset = 0 };
    }

    const remaining = total_count - @as(u16, @truncate(sectors_before));
    const chunk_size = @min(remaining, max_chunk_size);

    return .{
        .count = @as(u8, @truncate(chunk_size)),
        .offset = sectors_before * 512,
    };
}

fn getTotalChunks(count: u16) usize {
    const max_chunk_size: u16 = 255;
    return (count + max_chunk_size - 1) / max_chunk_size;
}
