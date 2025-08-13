const ft = @import("ft");
const cpu = @import("../../cpu.zig");
const timer = @import("../../timer.zig");
const scheduler = @import("../../task/scheduler.zig");
const constants = @import("constants.zig");
const types = @import("types.zig");

// === WAIT FUNCTIONS ===

/// Wait for drive ready without interrupts (polling mode)
pub fn waitForReadyPolling(base: u16, timeout_ms: usize) !u8 {
    const deadline = timer.get_time_since_boot() + timeout_ms;
    var status: u8 = 0;

    while (true) {
        status = cpu.inb(base + constants.ATA.REG_STATUS);
        if ((status & constants.ATA.STATUS_BUSY) == 0) return status;
        if (timer.get_time_since_boot() >= deadline) return error.Timeout;
        cpu.io_wait();
    }
}

/// Wait for data ready without interrupts (polling mode)
pub fn waitForDataPolling(base: u16, timeout_ms: usize) !u8 {
    const deadline = timer.get_time_since_boot() + timeout_ms;
    var status: u8 = 0;

    while (true) {
        status = cpu.inb(base + constants.ATA.REG_STATUS);
        if ((status & (constants.ATA.STATUS_BUSY | constants.ATA.STATUS_DRQ)) == constants.ATA.STATUS_DRQ)
            return status;
        if (timer.get_time_since_boot() >= deadline) return error.Timeout;
        cpu.io_wait();
    }
}

/// Wait for drive ready with scheduler yielding
pub fn waitForReadyAsync(_: u16, ctrl: u16, timeout_ms: usize) !u8 {
    const deadline = timer.get_time_since_boot() + timeout_ms;
    var status: u8 = 0;

    while (true) {
        status = cpu.inb(ctrl + constants.ATA.REG_ALT_STATUS);
        if ((status & constants.ATA.STATUS_BUSY) == 0) return status;
        if (timer.get_time_since_boot() >= deadline) return error.Timeout;
        scheduler.schedule();
    }
}

/// Wait for data ready with scheduler yielding
pub fn waitForDataAsync(_: u16, ctrl: u16, timeout_ms: usize) !u8 {
    const deadline = timer.get_time_since_boot() + timeout_ms;
    var status: u8 = 0;

    while (true) {
        status = cpu.inb(ctrl + constants.ATA.REG_ALT_STATUS);
        if (status & constants.ATA.STATUS_ERROR != 0) return status;
        if ((status & (constants.ATA.STATUS_BUSY | constants.ATA.STATUS_DRQ)) == constants.ATA.STATUS_DRQ)
            return status;
        if (timer.get_time_since_boot() >= deadline) return error.Timeout;
        scheduler.schedule();
    }
}

// === ERROR PARSING ===

/// Parse ATA error register and return appropriate error type
pub fn parseATAError(base: u16) types.Error {
    const err = cpu.inb(base + constants.ATA.REG_ERROR_READ);
    if (err & constants.ATA.ERROR_BAD_BLOCK != 0) return error.BadBlock;
    if (err & constants.ATA.ERROR_UNCORRECTABLE != 0) return error.UncorrectableError;
    if (err & constants.ATA.ERROR_MEDIA_CHANGED != 0) return error.MediaChanged;
    if (err & constants.ATA.ERROR_ID_MARK_NOT_FOUND != 0) return error.SectorNotFound;
    if (err & constants.ATA.ERROR_MEDIA_CHANGE_REQ != 0) return error.MediaChangeRequested;
    if (err & constants.ATA.ERROR_CMD_ABORTED != 0) return error.CommandAborted;
    if (err & constants.ATA.ERROR_TRACK0_NOT_FOUND != 0) return error.Track0NotFound;
    if (err & constants.ATA.ERROR_ADDR_MARK_NOT_FOUND != 0) return error.AddressMarkNotFound;
    return error.UnknownError;
}

/// Parse ATAPI error register and return appropriate error type
pub fn parseATAPIError(error_reg: u8) types.Error {
    const sense_key = (error_reg >> 4) & 0x0F;

    return switch (sense_key) {
        0x00 => error.UnknownError,
        0x01 => error.WriteError,
        0x02 => error.MediaNotReady,
        0x03 => error.UncorrectableError,
        0x04 => error.WriteError,
        0x05 => error.CommandAborted,
        0x06 => error.MediaChanged,
        0x07 => error.WriteError,
        else => error.UnknownError,
    };
}

// === PIO OPERATIONS ===

/// Read one sector (512 bytes) using PIO mode
pub fn readSectorPIO(base: u16, buf: []u8) void {
    for (0..256) |i| {
        const w = cpu.inw(base + constants.ATA.REG_DATA);
        buf[i * 2] = @truncate(w);
        buf[i * 2 + 1] = @truncate(w >> 8);
    }
}

/// Write one sector (512 bytes) using PIO mode
pub fn writeSectorPIO(base: u16, buf: []const u8) void {
    for (0..256) |i| {
        const low = buf[i * 2];
        const high = buf[i * 2 + 1];
        const w: u16 = (@as(u16, high) << 8) | low;
        cpu.outw(base + constants.ATA.REG_DATA, w);
    }
}

/// Select LBA device with proper flags
pub fn selectLBADevice(drive: types.DriveInfo.DrivePosition, lba: u32) u8 {
    const baseFlag: u8 = 0xE0; // LBA mode + always set bits
    const selFlag: u8 = if (drive == .Master) 0 else 0x10;
    return baseFlag | selFlag | @as(u8, @intCast((lba >> 24) & 0x0F));
}
