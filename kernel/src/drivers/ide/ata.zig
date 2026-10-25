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

// ATA controllers have a maximum number of sectors per command:
//   - LBA28: max 256 sectors
//   - LBA48: max 65536 sectors
//
// To transfer more sectors than the limit, we split the operation into "chunks".

/// Returns how many ATA commands are needed.
fn getTotalChunks(count: u32) usize {
    const max_chunk_size: u16 = 255;
    return (count + max_chunk_size - 1) / max_chunk_size;
}

/// Returns the LBA and sector count for a specific chunk.
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
        .count = @intCast(chunk_size),
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
        const lba32: u32 = @intCast(chunk_lba);

        // 1. Select the specific drive (Master/Slave) and set the top 4 bits of LBA
        common.selectDevice(op.channel.base, types.DeviceRegister.ataLBA28(op.position, op.lba));

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
    cpu.insw(channel.base + constants.ATA.REG_DATA, &raw);

    // Read status to clear any pending flags
    _ = cpu.inb(channel.base + constants.ATA.REG_STATUS);

    // Extract model string (Words 27-46 of REG_DATA response)
    std.mem.byteSwapAllFields([20]u16, raw[27..47]);
    var model: [40]u8 = .{0} ** 40;
    const trimmed = std.mem.trim(u8, std.mem.asBytes(raw[27..47]), " \x00");
    @memcpy(model[0..trimmed.len], trimmed);

    // Extract total sectors (Words 60-61 for LBA28)
    // Word 60: Low 16 bits of LBA count
    // Word 61: High 16 bits of LBA count
    // Note: For drives > 128GB (LBA48), we should look at words 100-103.
    // This driver currently assumes LBA28 capacity for simplicity (max 128GB support).
    const sec_lo: u32 = raw[60];
    const sec_hi: u32 = raw[61];
    const total: u32 = (sec_hi << 16) | sec_lo;

    logger.debug("identified {s} {s}: {s} ({} sectors)", .{
        @tagName(channel.channel_type),
        @tagName(position),
        model,
        total,
    });

    return DriveInfo{
        .drive_type = .ATA,
        .channel = channel.channel_type,
        .position = position,
        .model = model,
        .capacity = Capacity{ .sectors = total, .sector_size = 512 },
        .removable = false,
    };
}

/// Detect ATA drive presence and identify it.
/// Sequence: SELECT -> RESET STATUS -> SEND IDENTIFY -> WAIT -> READ DATA
pub fn detectDrive(channel: *const Channel, position: Channel.DrivePosition) ?DriveInfo {
    // 1. Select drive
    common.selectDevice(channel.base, types.DeviceRegister.select(position));

    cpu.io_wait();

    // 2. Clear status by reading it (dummy read)
    _ = cpu.inb(channel.base + constants.ATA.REG_STATUS);

    // 3. Send IDENTIFY command (0xEC)
    // This asks the drive to return a 512-byte block describing its features.
    cpu.outb(channel.base + constants.ATA.REG_COMMAND, constants.ATA.CMD_IDENTIFY);
    cpu.io_wait();

    // 4. Check if a drive exists
    // If Status is 0, no drive is present.
    const status = cpu.inb(channel.base + constants.ATA.REG_STATUS);
    if (status == 0 or status == 0xFF) {
        return null;
    }

    // 5. Wait for the data to be ready (DRQ set, BUSY clear)
    const wait_status = common.waitForData(channel.base, 1000) catch return null;

    if (wait_status.err) {
        return null;
    }

    // 6. Read and Parse the IDENTIFY data
    return parseIdentifyData(channel, position);
}
