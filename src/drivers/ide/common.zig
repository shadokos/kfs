const std = @import("std");
const cpu = @import("../../cpu.zig");
const ide = @import("ide.zig");
const timer = @import("../../timer.zig");
const constants = @import("constants.zig");
const types = @import("types.zig");
const DrivePosition = @import("channel.zig").DrivePosition;
const Channel = @import("channel.zig");
const common = @import("common.zig");

pub fn waitForReady(base: u16, timeout_ms: usize) types.IDEError!types.Status {
    const deadline = timer.get_time_since_boot() + timeout_ms;

    while (true) {
        const status: types.Status = @bitCast(cpu.inb(base + constants.ATA.REG_STATUS));
        if (!status.busy) {
            if (status.err) {
                return parseError(base);
            }
            return status;
        }
        if (timer.get_time_since_boot() >= deadline) {
            return types.IDEError.Timeout;
        }
        cpu.io_wait();
    }
}

pub fn waitForData(base: u16, timeout_ms: usize) types.IDEError!types.Status {
    const deadline = timer.get_time_since_boot() + timeout_ms;

    while (true) {
        const status: types.Status = @bitCast(cpu.inb(base + constants.ATA.REG_STATUS));
        if (status.drq and !status.busy) {
            return status;
        }
        if (timer.get_time_since_boot() >= deadline) {
            return types.IDEError.Timeout;
        }
        cpu.io_wait();
    }
}

pub fn waitForDataOrCompletion(base: u16, timeout_ms: usize) types.IDEError!types.Status {
    const deadline = timer.get_time_since_boot() + timeout_ms;

    while (true) {
        const status: types.Status = @bitCast(cpu.inb(base + constants.ATA.REG_STATUS));
        if (status.err) {
            return parseError(base);
        }
        if (!status.busy) {
            return status;
        }
        if (timer.get_time_since_boot() >= deadline) {
            return types.IDEError.Timeout;
        }
        cpu.io_wait();
    }
}

pub fn readSectorPIO(base: u16, buf: []u8) void {
    for (0..256) |i| {
        const w = cpu.inw(base + constants.ATA.REG_DATA);
        buf[i * 2] = @truncate(w);
        buf[i * 2 + 1] = @truncate(w >> 8);
    }
}

pub fn writeSectorPIO(base: u16, buf: []const u8) void {
    for (0..256) |i| {
        const low = buf[i * 2];
        const high = buf[i * 2 + 1];
        const w: u16 = (@as(u16, high) << 8) | low;
        cpu.outw(base + constants.ATA.REG_DATA, w);
    }
}

pub fn parseError(base: u16) types.IDEError {
    const err = cpu.inb(base + constants.ATA.REG_ERROR_READ);
    if (err & constants.ATA.ERROR_BAD_BLOCK != 0) return types.IDEError.BadBlock;
    if (err & constants.ATA.ERROR_UNCORRECTABLE != 0) return types.IDEError.UncorrectableError;
    if (err & constants.ATA.ERROR_MEDIA_CHANGED != 0) return types.IDEError.MediaChanged;
    if (err & constants.ATA.ERROR_ID_MARK_NOT_FOUND != 0) return types.IDEError.SectorNotFound;
    if (err & constants.ATA.ERROR_MEDIA_CHANGE_REQ != 0) return types.IDEError.MediaChangeRequested;
    if (err & constants.ATA.ERROR_CMD_ABORTED != 0) return types.IDEError.CommandAborted;
    if (err & constants.ATA.ERROR_TRACK0_NOT_FOUND != 0) return types.IDEError.Track0NotFound;
    if (err & constants.ATA.ERROR_ADDR_MARK_NOT_FOUND != 0) return types.IDEError.AddressMarkNotFound;
    return types.IDEError.UnknownError;
}

pub fn waitNs(ns: u32) void {
    for (0..ns / 30) |_| {
        cpu.io_wait();
    }
}

/// Select LBA device with proper flags
pub fn selectLBADevice(drive_type: ide.DriveType, op: *@import("ide.zig").IDEOperation) void {
    const reg: u8 = @bitCast(switch (drive_type) {
        .ATA => types.DeviceRegister.ataLBA28(op.position, op.lba),
        .ATAPI => types.DeviceRegister.select(op.position),
        .Unknown => unreachable,
    });

    cpu.outb(op.channel.base + constants.ATA.REG_DEVICE, reg);
    cpu.io_wait();
}
