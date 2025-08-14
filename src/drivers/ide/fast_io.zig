// src/drivers/ide/fast_io.zig
const std = @import("std");
const cpu = @import("../../cpu.zig");
const timer = @import("../../timer.zig");
const scheduler = @import("../../task/scheduler.zig");
const logger = std.log.scoped(.ide_fast_io);

const constants = @import("constants.zig");
const types = @import("types.zig");
const common = @import("common.zig");
const Channel = @import("channel.zig");

// === FAST I/O CONFIGURATION ===

pub const IOMode = enum {
    Polling,        // Pure polling, no interrupts
    Interrupt,      // Pure interrupt-driven
    Adaptive,       // Hybrid: polling first, then interrupts
};

pub const FastIOConfig = struct {
    // Thresholds for adaptive mode
    polling_timeout_us: u32 = 1000,    // Poll for 1ms before switching to interrupts
    max_polling_sectors: u16 = 16,     // Use polling for <= 16 sectors

    // Performance tuning
    polling_delay_ns: u32 = 100,       // Delay between polling iterations (in nanoseconds)
    yield_threshold_us: u32 = 10000,   // Yield to scheduler after 10ms of polling

    // Mode selection
    default_mode: IOMode = .Adaptive,
    force_polling_for_cache: bool = true,  // Always use polling for single-sector cache operations
};

var config = FastIOConfig{};

// === FAST POLLING OPERATIONS ===

/// Fast polling read without scheduler involvement
pub fn fastPollRead(
    channel: *Channel,
    drive: types.DriveInfo.DrivePosition,
    lba: u32,
    count: u16,
    buffer: []u8,
) !void {
    const start_time = timer.get_utime_since_boot();

    // Select drive and LBA mode
    const regDev = common.selectLBADevice(drive, lba);
    cpu.outb(channel.base + constants.ATA.REG_DEVICE, regDev);

    // Minimal delay for drive selection
    for (0..4) |_| cpu.io_wait();

    // Wait for drive ready with fast polling
    _ = try fastWaitReady(channel.base, 1000);

    // Setup command
    cpu.outb(channel.base + constants.ATA.REG_SEC_COUNT, @truncate(count));
    cpu.outb(channel.base + constants.ATA.REG_LBA_LOW, @truncate(lba));
    cpu.outb(channel.base + constants.ATA.REG_LBA_MID, @truncate(lba >> 8));
    cpu.outb(channel.base + constants.ATA.REG_LBA_HIGH, @truncate(lba >> 16));

    // Send READ command
    cpu.outb(channel.base + constants.ATA.REG_COMMAND, constants.ATA.CMD_READ_SECTORS);

    // Read all sectors with fast polling
    var sectors_read: u16 = 0;
    while (sectors_read < count) : (sectors_read += 1) {
        _ = try fastWaitData(channel.base, 5000);

        const offset = @as(usize, sectors_read) * 512;
        fastReadSector(channel.base, buffer[offset..offset + 512]);

        // Minimal yielding to prevent system freeze on large transfers
        if (timer.get_utime_since_boot() - start_time > config.yield_threshold_us) {
            scheduler.schedule();
        }
    }
}

/// Fast polling write without scheduler involvement
pub fn fastPollWrite(
    channel: *Channel,
    drive: types.DriveInfo.DrivePosition,
    lba: u32,
    count: u16,
    buffer: []const u8,
) !void {
    const start_time = timer.get_utime_since_boot();

    // Select drive and LBA mode
    const regDev = common.selectLBADevice(drive, lba);
    cpu.outb(channel.base + constants.ATA.REG_DEVICE, regDev);

    // Minimal delay for drive selection
    for (0..4) |_| cpu.io_wait();

    // Wait for drive ready with fast polling
    _ = try fastWaitReady(channel.base, 1000);

    // Setup command
    cpu.outb(channel.base + constants.ATA.REG_SEC_COUNT, @truncate(count));
    cpu.outb(channel.base + constants.ATA.REG_LBA_LOW, @truncate(lba));
    cpu.outb(channel.base + constants.ATA.REG_LBA_MID, @truncate(lba >> 8));
    cpu.outb(channel.base + constants.ATA.REG_LBA_HIGH, @truncate(lba >> 16));

    // Send WRITE command
    cpu.outb(channel.base + constants.ATA.REG_COMMAND, constants.ATA.CMD_WRITE_SECTORS);

    // Write all sectors with fast polling
    var sectors_written: u16 = 0;
    while (sectors_written < count) : (sectors_written += 1) {
        _ = try fastWaitData(channel.base, 5000);

        const offset = @as(usize, sectors_written) * 512;
        fastWriteSector(channel.base, buffer[offset..offset + 512]);

        // Minimal yielding to prevent system freeze on large transfers
        if (timer.get_utime_since_boot() - start_time > config.yield_threshold_us) {
            scheduler.schedule();
        }
    }

    // Wait for final completion
    _ = try fastWaitReady(channel.base, 1000);
}

// === ADAPTIVE MODE ===

/// Adaptive read that switches between polling and interrupts based on heuristics
pub fn adaptiveRead(
    channel: *Channel,
    request: *types.Request,
) !void {
    // Use polling for small transfers or cache operations
    if (request.count <= config.max_polling_sectors or config.force_polling_for_cache) {
        // Convert request to polling operation
        const drive_info = @import("controller.zig").getDriveInfo(
            if (request.channel == .Primary) 0 else 2
        ) orelse return error.InvalidDrive;
        _  = drive_info;

        try fastPollRead(
            channel,
            request.drive,
            request.lba,
            request.count,
            request.buffer.read,
        );

        request.completed = true;
        channel.queue.try_unblock();
    } else {
        // Use interrupt mode for large transfers
        try @import("ata.zig").sendCommandToHardware(channel, request);
    }
}

/// Adaptive write that switches between polling and interrupts based on heuristics
pub fn adaptiveWrite(
    channel: *Channel,
    request: *types.Request,
) !void {
    // Use polling for small transfers or cache operations
    if (request.count <= config.max_polling_sectors or config.force_polling_for_cache) {
        try fastPollWrite(
            channel,
            request.drive,
            request.lba,
            request.count,
            request.buffer.write,
        );

        request.completed = true;
        channel.queue.try_unblock();
    } else {
        // Use interrupt mode for large transfers
        try @import("ata.zig").sendCommandToHardware(channel, request);
    }
}

// === HELPER FUNCTIONS ===

/// Fast wait for ready without scheduler
inline fn fastWaitReady(base: u16, timeout_us: u32) !u8 {
    const deadline = timer.get_utime_since_boot() + timeout_us;
    var spin_count: u32 = 0;

    while (timer.get_utime_since_boot() < deadline) {
        const status = cpu.inb(base + constants.ATA.REG_STATUS);

        if ((status & constants.ATA.STATUS_BUSY) == 0) {
            return status;
        }

        // Adaptive spinning: start with tight loop, then add delays
        spin_count += 1;
        if (spin_count > 1000) {
            // After 1000 iterations, add small delays
            for (0..config.polling_delay_ns / 30) |_| {
                cpu.io_wait();
            }
        }
    }

    return error.Timeout;
}

/// Fast wait for data without scheduler
inline fn fastWaitData(base: u16, timeout_us: u32) !u8 {
    const deadline = timer.get_utime_since_boot() + timeout_us;
    var spin_count: u32 = 0;

    while (timer.get_utime_since_boot() < deadline) {
        const status = cpu.inb(base + constants.ATA.REG_STATUS);

        if (status & constants.ATA.STATUS_ERROR != 0) {
            return status;
        }

        if ((status & (constants.ATA.STATUS_BUSY | constants.ATA.STATUS_DRQ)) == constants.ATA.STATUS_DRQ) {
            return status;
        }

        // Adaptive spinning
        spin_count += 1;
        if (spin_count > 1000) {
            for (0..config.polling_delay_ns / 30) |_| {
                cpu.io_wait();
            }
        }
    }

    return error.Timeout;
}

/// Fast sector read with unrolled loop for better performance
inline fn fastReadSector(base: u16, buf: []u8) void {
    // Read 512 bytes as 256 words
    // Unroll loop for better performance
    var i: usize = 0;
    while (i < 256) : (i += 4) {
        // Read 4 words at a time (8 bytes)
        const w0 = cpu.inw(base + constants.ATA.REG_DATA);
        const w1 = cpu.inw(base + constants.ATA.REG_DATA);
        const w2 = cpu.inw(base + constants.ATA.REG_DATA);
        const w3 = cpu.inw(base + constants.ATA.REG_DATA);

        buf[i * 2] = @truncate(w0);
        buf[i * 2 + 1] = @truncate(w0 >> 8);
        buf[i * 2 + 2] = @truncate(w1);
        buf[i * 2 + 3] = @truncate(w1 >> 8);
        buf[i * 2 + 4] = @truncate(w2);
        buf[i * 2 + 5] = @truncate(w2 >> 8);
        buf[i * 2 + 6] = @truncate(w3);
        buf[i * 2 + 7] = @truncate(w3 >> 8);
    }
}

/// Fast sector write with unrolled loop for better performance
inline fn fastWriteSector(base: u16, buf: []const u8) void {
    // Write 512 bytes as 256 words
    // Unroll loop for better performance
    var i: usize = 0;
    while (i < 256) : (i += 4) {
        // Write 4 words at a time (8 bytes)
        const w0: u16 = (@as(u16, buf[i * 2 + 1]) << 8) | buf[i * 2];
        const w1: u16 = (@as(u16, buf[i * 2 + 3]) << 8) | buf[i * 2 + 2];
        const w2: u16 = (@as(u16, buf[i * 2 + 5]) << 8) | buf[i * 2 + 4];
        const w3: u16 = (@as(u16, buf[i * 2 + 7]) << 8) | buf[i * 2 + 6];

        cpu.outw(base + constants.ATA.REG_DATA, w0);
        cpu.outw(base + constants.ATA.REG_DATA, w1);
        cpu.outw(base + constants.ATA.REG_DATA, w2);
        cpu.outw(base + constants.ATA.REG_DATA, w3);
    }
}

// === CONFIGURATION API ===

pub fn setMode(mode: IOMode) void {
    config.default_mode = mode;
    logger.info("Fast I/O mode set to: {s}", .{@tagName(mode)});
}

pub fn getConfig() *FastIOConfig {
    return &config;
}

pub fn tuneForLatency() void {
    config.polling_timeout_us = 500;
    config.max_polling_sectors = 32;
    config.polling_delay_ns = 50;
    config.force_polling_for_cache = true;
    logger.info("Tuned for low latency", .{});
}

pub fn tuneForThroughput() void {
    config.polling_timeout_us = 2000;
    config.max_polling_sectors = 8;
    config.polling_delay_ns = 200;
    config.force_polling_for_cache = false;
    logger.info("Tuned for high throughput", .{});
}

pub fn tuneForPowerSaving() void {
    config.polling_timeout_us = 100;
    config.max_polling_sectors = 4;
    config.polling_delay_ns = 1000;
    config.force_polling_for_cache = false;
    config.default_mode = .Interrupt;
    logger.info("Tuned for power saving", .{});
}