const std = @import("std");
const cpu = @import("../../cpu.zig");
const ide = @import("ide.zig");
const timer = @import("../../timer.zig");
const constants = @import("constants.zig");
const types = @import("types.zig");
const DrivePosition = @import("channel.zig").DrivePosition;
const Channel = @import("channel.zig");
const common = @import("common.zig");

pub fn waitForReady(base: u16, timeout_ms: usize) types.IDEError!u8 {
    const deadline = timer.get_time_since_boot() + timeout_ms;

    while (true) {
        const status = cpu.inb(base + constants.ATA.REG_STATUS);
        if ((status & constants.ATA.STATUS_BUSY) == 0) {
            if (status & constants.ATA.STATUS_ERROR != 0) {
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

pub fn waitForData(base: u16, timeout_ms: usize) types.IDEError!u8 {
    const deadline = timer.get_time_since_boot() + timeout_ms;

    while (true) {
        const status = cpu.inb(base + constants.ATA.REG_STATUS);
        if ((status & (constants.ATA.STATUS_BUSY | constants.ATA.STATUS_DRQ)) == constants.ATA.STATUS_DRQ) {
            return status;
        }
        if (timer.get_time_since_boot() >= deadline) {
            return types.IDEError.Timeout;
        }
        cpu.io_wait();
    }
}

pub fn waitForDataOrCompletion(base: u16, timeout_ms: usize) types.IDEError!u8 {
    const deadline = timer.get_time_since_boot() + timeout_ms;

    while (true) {
        const status = cpu.inb(base + constants.ATA.REG_STATUS);
        if (status & constants.ATA.STATUS_ERROR != 0) {
            return parseError(base);
        }
        if ((status & constants.ATA.STATUS_BUSY) == 0) {
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
    switch (drive_type) {
        .ATA => {
            const baseFlag: u8 = 0xE0; // LBA mode + always set bits
            const selFlag: u8 = if (op.position == DrivePosition.Master) 0 else 0x10;
            const regDev = baseFlag | selFlag | @as(u8, @intCast((op.lba >> 24) & 0x0F));

            cpu.outb(op.channel.base + constants.ATA.REG_DEVICE, regDev);
        },
        .ATAPI => {
            const baseFlag: u8 = 0xA0; // ATAPI LBA mode + always set bits
            const selFlag: u8 = if (op.position == DrivePosition.Master) 0 else 0x10;
            const regDev = baseFlag | selFlag;

            cpu.outb(op.channel.base + constants.ATA.REG_DEVICE, regDev);
        },
        .Unknown => unreachable,
    }

    // common.waitNs(400);
    cpu.io_wait();
}
