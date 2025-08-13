const std = @import("std");
const DefaultShell = @import("shell/default/shell.zig");
const tty = @import("./tty/tty.zig");
const ide = @import("./drivers/ide/ide.zig");
const timer = @import("timer.zig");
const logger = std.log.scoped(.main);

pub fn main(_: usize) u8 {
    demoStorageCapabilities() catch {};

    // Start shell
    var shell = DefaultShell.Shell.init(tty.get_reader(), tty.get_writer(), .{}, .{
        .on_init = DefaultShell.on_init,
        .pre_prompt = DefaultShell.pre_process,
    });
    while (true) shell.process_line();
}

// === STORAGE CAPABILITIES DEMONSTRATION ===

/// Demonstrate storage capabilities with all detected drives
fn demoStorageCapabilities() !void {
    logger.info("=== Storage capabilities demonstration ===", .{});

    // Test all detected drives
    for (0..ide.controller.getDriveCount()) |i| {
        const drive_info = ide.controller.getDriveInfo(i) orelse continue;

        logger.info("Testing drive {} ({s})...", .{ i, drive_info.drive_type.toString() });

        if (drive_info.isATA()) {
            try testATADrive(i, drive_info);
        } else if (drive_info.isATAPI()) {
            try testATAPIDrive(i, drive_info);
        }
    }
}

// === ATAPI DRIVE TESTING ===

/// Test ATAPI drive operations (CD-ROM/DVD)
fn testATAPIDrive(drive_idx: usize, _: ide.types.DriveInfo) !void {
    logger.info("Testing ATAPI drive {} (CD-ROM/DVD)...", .{drive_idx});

    // Test TEST UNIT READY command
    try testATAPIUnitReady(drive_idx);

    // Test read capacity
    const capacity = try ide.getDriveCapacity(drive_idx);
    logger.info("ATAPI drive {} capacity: {} {s} ({} sectors, {} bytes)", .{
        drive_idx,
        capacity.totalSizeAutoUnit(),
        @tagName(capacity.unit),
        capacity.sectors,
        capacity.sector_size,
    });

    // Test sector read
    try testATAPIReadSector(drive_idx);
}

/// Test reading first sector from ATAPI drive
fn testATAPIReadSector(drive_idx: usize) !void {
    logger.info("ATAPI: Testing first sector read...", .{});

    var buffer: [2048]u8 = undefined; // Standard CD-ROM sector

    ide.read(drive_idx, 0, 1, &buffer, 5000) catch |err| {
        logger.warn("ATAPI sector read failed: {s}", .{@errorName(err)});
        return;
    };

    logger.info("ATAPI: Sector read successful! {} bytes read", .{buffer.len});
    @import("debug.zig").memory_dump(@intFromPtr(&buffer), @intFromPtr(&buffer) + buffer.len);
}

/// Test ATAPI TEST UNIT READY command
pub fn testATAPIUnitReady(drive_idx: usize) !void {
    logger.info("ATAPI: Test Unit Ready...", .{});

    // SCSI TEST_UNIT_READY packet
    var packet: [ide.constants.ATAPI.PACKET_SIZE]u8 = .{0} ** ide.constants.ATAPI.PACKET_SIZE;
    packet[0] = ide.constants.ATAPI.CMD_TEST_UNIT_READY;
    // All other bytes remain 0

    var response: [0]u8 = undefined; // TEST_UNIT_READY returns no data

    const bytes_read = ide.atapi.sendCommand(drive_idx, &packet, &response, 10000) catch |err| {
        switch (err) {
            error.MediaNotReady => {
                logger.info("ATAPI: Media not ready - no media inserted", .{});
                return;
            },
            error.Timeout => {
                logger.info("ATAPI: Timeout - drive not responding", .{});
                return;
            },
            else => {
                logger.err("ATAPI: Test Unit Ready error: {s}", .{@errorName(err)});
                return;
            },
        }
    };

    // For TEST_UNIT_READY, 0 bytes is normal if command succeeds
    logger.info("ATAPI: Drive ready (response: {} bytes)", .{bytes_read});
}

// === ATA DRIVE TESTING ===

/// Test ATA drive read operations
fn testATADrive(drive_idx: usize, _: ide.types.DriveInfo) !void {
    var buffer: [1024]u8 = undefined; // Buffer for 2 sectors

    logger.info("Testing ATA drive {} read (LBA 0-1)...", .{drive_idx});

    // Test reading first sectors
    ide.read(drive_idx, 0, 2, &buffer, 5000) catch |err| {
        logger.err("ATA read error: {s}", .{@errorName(err)});
        return;
    };

    logger.info("Successfully read ATA drive {}: {} bytes", .{ drive_idx, buffer.len });
    @import("debug.zig").memory_dump(@intFromPtr(&buffer), @intFromPtr(&buffer) + buffer.len);

    // Write (WARNING: Modifies the disk!)
    // logger.info("Testing ATA drive {} write...", .{drive_idx});

    // @memcpy(buffer[0..6], "// YEP");
    // ide.write(drive_idx, 0, 2, &buffer, 5000) catch |err| {
    //     logger.err("ATA write error: {s}", .{@errorName(err)});
    //     return;
    // };
}
