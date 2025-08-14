const std = @import("std");
const logger = std.log.scoped(.ide);

pub const constants = @import("constants.zig");
pub const types = @import("types.zig");
pub const ata = @import("ata.zig");
pub const atapi = @import("atapi.zig");
pub const controller = @import("controller.zig");

// === GENERAL API ===

/// Read data from a drive (auto-detects type)
pub fn read(
    drive_idx: usize,
    lba: u32,
    count: u16,
    buf: []u8,
    timeout: ?usize,
) types.Error!void {
    const drive_info = controller.getDriveInfo(drive_idx) orelse {
        return error.InvalidDrive;
    };

    return switch (drive_info.drive_type) {
        .ATA => ata.read(drive_idx, lba, count, buf, timeout),
        .ATAPI => atapi.readCDROM(drive_idx, lba, count, buf, timeout),
        else => error.InvalidDrive,
    };
}

/// Write data to a drive (ATA only)
pub fn write(
    drive_idx: usize,
    lba: u32,
    count: u16,
    buf: []const u8,
    timeout: ?usize,
) types.Error!void {
    const drive_info = controller.getDriveInfo(drive_idx) orelse {
        return error.InvalidDrive;
    };

    return switch (drive_info.drive_type) {
        .ATA => ata.write(drive_idx, lba, count, buf, timeout),
        .ATAPI => error.InvalidDrive, // CD-ROM are read-only
        else => error.InvalidDrive,
    };
}

// === DRIVE INFORMATION API ===

/// Get drive information by index
pub fn getDriveInfo(drive_idx: usize) ?types.DriveInfo {
    return controller.getDriveInfo(drive_idx);
}

/// Get total number of detected drives
pub fn getDriveCount() usize {
    return controller.getDriveCount();
}

/// Get drive capacity
pub fn getDriveCapacity(drive_idx: usize) types.Error!types.Capacity {
    const drive_info = controller.getDriveInfo(drive_idx) orelse {
        return error.InvalidDrive;
    };

    // For ATAPI drives, capacity might change if media is inserted/removed
    if (drive_info.drive_type == .ATAPI) {
        // TODO: Implement dynamic capacity reading for ATAPI
        // For now, return the cached capacity
    }

    return drive_info.capacity;
}

/// Check if a drive is removable
pub fn isDriveRemovable(drive_idx: usize) bool {
    const drive_info = controller.getDriveInfo(drive_idx) orelse return false;
    return drive_info.removable;
}

/// Get drive type
pub fn getDriveType(drive_idx: usize) ?types.DriveType {
    const drive_info = controller.getDriveInfo(drive_idx) orelse return null;
    return drive_info.drive_type;
}

// === UTILITY FUNCTIONS ===

/// List all drives (wrapper for controller function)
pub fn listDrives() void {
    controller.listDrives();
}

// === INITIALIZATION ===

/// Initialize the IDE driver system
pub fn init() !void {
    try controller.init();
    controller.listDrives();
    logger.info("{d} drives initialized", .{controller.getDriveCount()});
    logger.info("IDE driver initialized with PCI support", .{});
}

/// Clean up IDE resources
pub fn deinit() void {
    controller.deinit();
}
