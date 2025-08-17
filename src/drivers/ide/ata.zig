const std = @import("std");
const cpu = @import("../../cpu.zig");
const ide = @import("ide.zig");
const timer = @import("../../timer.zig");
const constants = @import("constants.zig");
const types = @import("types.zig");
const common = @import("common.zig");
const Channel = @import("channel.zig");

const IDEOperation = ide.IDEOperation;
const DriveInfo = types.DriveInfo;
const IDEError = types.IDEError;
const Capacity = types.Capacity;

const logger = std.log.scoped(.ATA);

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

pub fn performPolling(op: *IDEOperation) IDEError!void {
    if (op.lba > 0xFFFFFFF) return IDEError.OutOfBounds;

    const total_chunks = getTotalChunks(op.count);

    // Perform the operation in chunks up to 255 sectors (ATA PIO limitation)
    for (0..total_chunks) |chunk_idx| {
        const chunk_info = getChunkInfo(op.count, chunk_idx);
        if (chunk_info.count == 0) break;

        const chunk_lba = op.lba + (chunk_idx * 255);
        const lba32 = @as(u32, @truncate(chunk_lba));

        common.selectLBADevice(.ATA, op);

        _ = try common.waitForReady(op.channel.base, 1000);

        cpu.outb(op.channel.base + constants.ATA.REG_SEC_COUNT, chunk_info.count);
        cpu.outb(op.channel.base + constants.ATA.REG_LBA_LOW, @truncate(lba32));
        cpu.outb(op.channel.base + constants.ATA.REG_LBA_MID, @truncate(lba32 >> 8));
        cpu.outb(op.channel.base + constants.ATA.REG_LBA_HIGH, @truncate(lba32 >> 16));

        const cmd = if (op.is_write) constants.ATA.CMD_WRITE_SECTORS else constants.ATA.CMD_READ_SECTORS;
        cpu.outb(op.channel.base + constants.ATA.REG_COMMAND, cmd);

        for (0..chunk_info.count) |i| {
            _ = try common.waitForData(op.channel.base, 5000);

            const offset = chunk_info.offset + i * 512;
            if (op.is_write) {
                common.writeSectorPIO(op.channel.base, op.buffer.write[offset .. offset + 512]);
            } else {
                common.readSectorPIO(op.channel.base, op.buffer.read[offset .. offset + 512]);
            }
        }

        if (op.is_write) {
            _ = try common.waitForReady(op.channel.base, 1000);
        }
    }
}

/// Parse ATA IDENTIFY response
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

    // Extract total sectors
    const sec_lo: u32 = raw[60];
    const sec_hi: u32 = raw[61];
    const total: u64 = (@as(u64, sec_hi) << 16) | sec_lo;

    logger.debug("identified {s} {s}: {s} ({} sectors)", .{
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

/// Detect ATA drive
pub fn detectDrive(channel: *const Channel, position: Channel.DrivePosition) !?DriveInfo {
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
    status = common.waitForData(channel.base, 1000) catch return null;

    if (status & constants.ATA.STATUS_ERROR != 0) {
        return null;
    }

    // Read IDENTIFY data
    return parseIdentifyData(channel, position);
}
