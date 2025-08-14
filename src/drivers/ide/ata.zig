const ft = @import("ft");
const cpu = @import("../../cpu.zig");
const logger = ft.log.scoped(.ata);

const types = @import("types.zig");
const constants = @import("constants.zig");
const common = @import("common.zig");
const Channel = @import("channel.zig");
const controller = @import("controller.zig");
const request_manager = @import("request_manager.zig");

// === PUBLIC API ===

/// Read data from ATA drive
pub fn read(drive_idx: usize, lba: u32, count: u16, buf: []u8, timeout: ?usize) types.Error!void {
    try performOperation(drive_idx, lba, count, buf, timeout, .read);
}

/// Write data to ATA drive
pub fn write(drive_idx: usize, lba: u32, count: u16, buf: []const u8, timeout: ?usize) types.Error!void {
    try performOperation(drive_idx, lba, count, @constCast(buf), timeout, .write);
}

// === INTERNAL OPERATIONS ===

fn performOperation(
    drive_idx: usize,
    lba: u32,
    count: u16,
    buf: []u8,
    timeout: ?usize,
    operation_type: enum { read, write },
) types.Error!void {
    if (drive_idx >= controller.getDriveCount()) return error.InvalidDrive;
    const drive_info = controller.getDriveInfo(drive_idx).?;
    if (!drive_info.isATA()) return error.InvalidDrive;
    if (count == 0) return error.InvalidCount;
    if (buf.len < @as(usize, count) * 512) return error.BufferTooSmall;

    // Handle 256 sector chunks
    var remaining = count;
    var current_lba = lba;
    var offset: usize = 0;

    while (remaining > 0) {
        const chunk = @min(remaining, 256);
        var request = types.Request{
            .channel = drive_info.channel,
            .drive = drive_info.drive,
            .command = switch (operation_type) {
                .read => constants.ATA.CMD_READ_SECTORS,
                .write => constants.ATA.CMD_WRITE_SECTORS,
            },
            .lba = current_lba,
            .count = chunk,
            .buffer = switch (operation_type) {
                .read => .{ .read = buf[offset .. offset + (@as(usize, chunk) * 512)] },
                .write => .{ .write = buf[offset .. offset + (@as(usize, chunk) * 512)] },
            },
            .is_atapi = false,
        };

        try request_manager.sendRequest(&request, timeout);

        remaining -= chunk;
        current_lba += chunk;
        offset += @as(usize, chunk) * 512;
    }
}

/// Send ATA command to hardware
pub fn sendCommandToHardware(channel: *Channel, request: *types.Request) !void {
    // Select drive and configure LBA mode
    const regDev = common.selectLBADevice(request.drive, request.lba);
    cpu.outb(channel.base + constants.ATA.REG_DEVICE, regDev);
    cpu.io_wait();

    _ = try channel.waitForReady();

    // Configure registers
    cpu.outb(channel.base + constants.ATA.REG_SEC_COUNT, @truncate(request.count));
    cpu.outb(channel.base + constants.ATA.REG_LBA_LOW, @truncate(request.lba));
    cpu.outb(channel.base + constants.ATA.REG_LBA_MID, @truncate(request.lba >> 8));
    cpu.outb(channel.base + constants.ATA.REG_LBA_HIGH, @truncate(request.lba >> 16));

    // Clear pending interrupts
    _ = cpu.inb(channel.base + constants.ATA.REG_STATUS);

    // Send command
    cpu.outb(channel.base + constants.ATA.REG_COMMAND, request.command);

    // Handle write operations
    if (request.command == constants.ATA.CMD_WRITE_SECTORS) {
        const status = try channel.waitForData();
        if (status & constants.ATA.STATUS_ERROR != 0) {
            request.err = common.parseATAError(channel.base);
            return request.err.?;
        }

        common.writeSectorPIO(channel.base, request.buffer.write[0..512]);
        request.current_sector = 1;
    }
}

/// Handle ATA interrupt
pub fn handleInterrupt(channel: *Channel, request: *types.Request, status: u8) void {
    _ = status;

    switch (request.command) {
        constants.ATA.CMD_READ_SECTORS => {
            const offset = request.current_sector * 512;
            common.readSectorPIO(channel.base, request.buffer.read[offset .. offset + 512]);
            request.current_sector += 1;

            if (request.current_sector >= request.count) {
                request.completed = true;
                channel.queue.try_unblock();
            }
        },
        constants.ATA.CMD_WRITE_SECTORS => {
            if (request.current_sector < request.count) {
                const offset = request.current_sector * 512;
                common.writeSectorPIO(channel.base, request.buffer.write[offset .. offset + 512]);
                request.current_sector += 1;
            } else {
                request.completed = true;
                channel.queue.try_unblock();
            }
        },
        else => {
            request.completed = true;
            channel.queue.try_unblock();
        },
    }
}
