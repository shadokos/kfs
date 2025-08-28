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

fn getTotalChunks(count: u32) usize {
    const max_chunk_size: u16 = 255;
    return (count + max_chunk_size - 1) / max_chunk_size;
}

fn getChunkInfo(total_count: u32, chunk_index: usize) struct { count: u8, offset_sectors: u32 } {
    const max_chunk_size: u32 = 255;

    // Calcul direct de l'offset
    const offset_sectors = chunk_index * max_chunk_size;

    if (offset_sectors >= total_count) {
        return .{ .count = 0, .offset_sectors = 0 };
    }

    const remaining = total_count - offset_sectors;
    const chunk_size = @min(remaining, max_chunk_size);

    return .{
        .count = @as(u8, @truncate(chunk_size)),
        .offset_sectors = offset_sectors,
    };
}

pub fn performPolling(op: *IDEOperation) IDEError!void {
    if (op.lba > 0xFFFFFFF) return IDEError.OutOfBounds;

    // ATA PIO (Programmed I/O) has a limitation: the Sector Count register is 8-bit.
    // This means we can maximally transfer 255 sectors (or 256 if 0 is interpreted as 256) per command.
    // To handle larger requests (e.g. 1MB read), we must split the operation into "chunks".
    const total_chunks = getTotalChunks(op.count);

    for (0..total_chunks) |chunk_idx| {
        const chunk_info = getChunkInfo(op.count, chunk_idx);
        if (chunk_info.count == 0) break;

        // Calculate the actual LBA for this specific chunk
        const chunk_lba = op.lba + chunk_info.offset_sectors;
        const lba32 = @as(u32, @truncate(chunk_lba));

        // 1. Select the specific drive (Master/Slave) and set the top 4 bits of LBA
        common.selectLBADevice(.ATA, op);

        // 2. Wait for the BUSY bit to clear before sending command parameters
        _ = try common.waitForReady(op.channel.base, 1000);

        // 3. Write command parameters to IO ports
        // sector_count: number of sectors to read/write for this chunk
        cpu.outb(op.channel.base + constants.ATA.REG_SEC_COUNT, chunk_info.count);
        // LBA Low/Mid/High: The lower 24 bits of the LBA address
        cpu.outb(op.channel.base + constants.ATA.REG_LBA_LOW, @truncate(lba32));
        cpu.outb(op.channel.base + constants.ATA.REG_LBA_MID, @truncate(lba32 >> 8));
        cpu.outb(op.channel.base + constants.ATA.REG_LBA_HIGH, @truncate(lba32 >> 16));

        const cmd = switch (op.io_type) {
            .Read => constants.ATA.CMD_READ_SECTORS,
            .Write => constants.ATA.CMD_WRITE_SECTORS,
        };
        // 4. Send the Command (starts the operation on the drive)
        cpu.outb(op.channel.base + constants.ATA.REG_COMMAND, cmd);

        // 5. Transfer data loop
        // For each sector in this chunk, we must wait for the drive to be ready (DRQ bit set)
        // and then transfer 512 bytes (256 words) via the Data Port.
        for (0..chunk_info.count) |i| {
            // Wait until drive requests data transfer (Data Request - DRQ)
            _ = try common.waitForData(op.channel.base, 5000);

            const buffer_offset = (chunk_info.offset_sectors + i) * 512;

            // PIO Data Register (0x1F0/0x170) is 16-bit wide.
            // We use helper functions to read/write 256 words (512 bytes) efficiently.
            if (op.io_type == .Write) {
                common.writeSectorPIO(op.channel.base, op.buffer.write[buffer_offset .. buffer_offset + 512]);
            } else {
                common.readSectorPIO(op.channel.base, op.buffer.read[buffer_offset .. buffer_offset + 512]);
            }
        }

        // 6. For Write operations, ensure the drive has finished writing the last sector
        if (op.io_type == .Write) {
            _ = try common.waitForReady(op.channel.base, 1000);
        }
    }
}

/// Parse ATA IDENTIFY response (512 bytes of information)
/// This function extracts the drive model and total capacity from the data block returned by the drive.
fn parseIdentifyData(channel: *const Channel, position: Channel.DrivePosition) DriveInfo {
    var raw: [256]u16 = undefined;
    // Read 256 words (512 bytes) from the Data Register
    for (0..256) |i| {
        raw[i] = cpu.inw(channel.base + constants.ATA.REG_DATA);
    }

    // Read status to clear any pending flags
    _ = cpu.inb(channel.base + constants.ATA.REG_STATUS);

    // Extract model string (Words 27-46)
    // The string is stored as a sequence of 16-bit words.
    // KEY DETAIL: Each word contains two ASCII characters, but they are SWAPPED (Big Endian in a Little Endian world).
    // Example: "QM" is stored as 0x4D51 ('M' << 8 | 'Q'). We must unswap them.
    var model_arr: [41]u8 = .{0} ** 41;
    var widx: usize = 27;
    var midx: usize = 0;
    while (widx <= 46) : (widx += 1) {
        const w = raw[widx];
        model_arr[midx] = @truncate(w >> 8); // High byte is the first character
        model_arr[midx + 1] = @truncate(w & 0xFF); // Low byte is the second character
        midx += 2;
    }

    // Trim trailing spaces to get a clean model name
    var model_len: usize = 40;
    while (model_len > 0) : (model_len -= 1) {
        if (model_arr[model_len - 1] != ' ' and model_arr[model_len - 1] != 0) break;
    }
    if (model_len < model_arr.len) model_arr[model_len] = 0;

    // Extract total sectors (Words 60-61 for LBA28)
    // Word 60: Low 16 bits of LBA count
    // Word 61: High 16 bits of LBA count
    // Note: For drives > 128GB (LBA48), we should look at words 100-103.
    // This driver currently assumes LBA28 capacity for simplicity (max 128GB support).
    const sec_lo: u32 = raw[60];
    const sec_hi: u32 = raw[61];
    const total: u32 = (@as(u32, sec_hi) << 16) | sec_lo;

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

/// Detect ATA drive presence and identify it.
/// Sequence: SELECT -> RESET STATUS -> SEND IDENTIFY -> WAIT -> READ DATA
pub fn detectDrive(channel: *const Channel, position: Channel.DrivePosition) ?DriveInfo {
    // 1. Select drive (0xA0 for Master, 0xB0 for Slave)
    const select: u8 = if (position == .Master) 0xA0 else 0xB0;
    cpu.outb(channel.base + constants.ATA.REG_DEVICE, select);
    cpu.io_wait();

    // 2. Clear status by reading it (dummy read)
    _ = cpu.inb(channel.base + constants.ATA.REG_STATUS);

    // 3. Send IDENTIFY command (0xEC)
    // This asks the drive to return a 512-byte block describing its features.
    cpu.outb(channel.base + constants.ATA.REG_COMMAND, constants.ATA.CMD_IDENTIFY);
    cpu.io_wait();

    // 4. Check if a drive exists
    // If Status is 0, no drive is present.
    var status = cpu.inb(channel.base + constants.ATA.REG_STATUS);
    if (status == 0 or status == 0xFF) {
        return null;
    }

    // 5. Wait for the data to be ready (DRQ set, BUSY clear)
    status = common.waitForData(channel.base, 1000) catch return null;

    if (status & constants.ATA.STATUS_ERROR != 0) {
        return null;
    }

    // 6. Read and Parse the IDENTIFY data
    return parseIdentifyData(channel, position);
}
