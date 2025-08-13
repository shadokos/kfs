const std = @import("std");
const pci = @import("../pci/pci.zig");
const cpu = @import("../../cpu.zig");
const ArrayList = std.ArrayList;
const logger = std.log.scoped(.ide_discovery);

const constants = @import("constants.zig");
const types = @import("types.zig");
const common = @import("common.zig");
const Channel = @import("channel.zig");

const allocator = @import("../../memory.zig").smallAlloc.allocator();

// === PCI CONTROLLER INFO ===

pub const PCIControllerInfo = struct {
    pci_device: pci.PCIDevice,
    interface: pci.IDEInterface,
};

// === PCI DISCOVERY ===

/// Discover PCI IDE controllers
pub fn discoverPCIControllers() !ArrayList(PCIControllerInfo) {
    var controllers = ArrayList(PCIControllerInfo).init(allocator);
    errdefer controllers.deinit();

    const ide_controllers = pci.findIDEControllers();

    if (ide_controllers) |controller_list| {
        defer allocator.free(controller_list);

        for (controller_list) |controller| {
            const interface = controller.getIDEInterface() orelse continue;

            logger.info("IDE controller found: {}:{}.{} - Interface: {s}", .{
                controller.bus,
                controller.device,
                controller.function,
                @tagName(interface),
            });

            controller.enableDevice();

            try controllers.append(PCIControllerInfo{
                .pci_device = controller,
                .interface = interface,
            });
        }
    }

    if (controllers.items.len == 0) {
        logger.warn("No IDE controllers found via PCI, using legacy ports", .{});
        try addLegacyController(&controllers);
    }

    return controllers;
}

/// Add legacy IDE controller
fn addLegacyController(controllers: *ArrayList(PCIControllerInfo)) !void {
    const legacy_device = pci.PCIDevice{
        .bus = 0,
        .device = 0,
        .function = 0,
        .vendor_id = 0x0000,
        .device_id = 0x0000,
        .class_code = .MassStorage,
        .subclass = 0x01,
        .prog_if = 0x00,
        .revision = 0,
        .header_type = 0,
        .bars = .{ 0x1F0, 0x3F6, 0x170, 0x376, 0x0000, 0 },
        .irq_line = 14,
        .irq_pin = 1,
    };

    try controllers.append(PCIControllerInfo{
        .pci_device = legacy_device,
        .interface = .ISACompatibility,
    });
}

// === DRIVE DETECTION ===

/// Detect ATA drive on specified channel and position
pub fn detectATADrive(channel: *Channel, drive: types.DriveInfo.DrivePosition) ?types.DriveInfo {
    // Select drive
    const select: u8 = if (drive == .Master) 0xA0 else 0xB0;
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
    status = common.waitForDataPolling(channel.base, 1000) catch return null;

    if (status & constants.ATA.STATUS_ERROR != 0) {
        return null;
    }

    // Read IDENTIFY data
    return parseATAIdentify(channel, drive);
}

/// Detect ATAPI drive on specified channel and position
pub fn detectATAPIDrive(channel: *Channel, drive: types.DriveInfo.DrivePosition) ?types.DriveInfo {
    // Select drive
    const select: u8 = if (drive == .Master) 0xA0 else 0xB0;
    cpu.outb(channel.base + constants.ATA.REG_DEVICE, select);
    cpu.io_wait();

    // Software reset
    cpu.outb(channel.ctrl, 0x04);
    cpu.io_wait();
    cpu.outb(channel.ctrl, 0x00);
    cpu.io_wait();

    // Wait for stabilization
    _ = common.waitForReadyPolling(channel.base, 1000) catch return null;

    // Check ATAPI signature
    const lba_mid = cpu.inb(channel.base + constants.ATA.REG_LBA_MID);
    const lba_high = cpu.inb(channel.base + constants.ATA.REG_LBA_HIGH);

    if (lba_mid == 0x14 and lba_high == 0xEB) {
        // ATAPI signature found
        logger.debug("ATAPI drive detected on {s} {s}", .{ @tagName(channel.channel), @tagName(drive) });

        // Send IDENTIFY PACKET DEVICE command
        cpu.outb(channel.base + constants.ATA.REG_COMMAND, constants.ATA.CMD_IDENTIFY_PACKET);
        cpu.io_wait();

        const status = common.waitForDataPolling(channel.base, 1000) catch return null;
        if (status & constants.ATA.STATUS_ERROR != 0) return null;

        return parseATAPIIdentify(channel, drive);
    }

    return null;
}

/// Parse ATA IDENTIFY response
fn parseATAIdentify(channel: *Channel, drive: types.DriveInfo.DrivePosition) ?types.DriveInfo {
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

    logger.debug("ATA {s} {s}: {s} ({} sectors)", .{
        @tagName(channel.channel),
        @tagName(drive),
        model_arr[0..model_len],
        total,
    });

    return types.DriveInfo{
        .drive_type = .ATA,
        .channel = channel.channel,
        .drive = drive,
        .model = model_arr,
        .capacity = types.Capacity.init(total, 512),
        .removable = false,
    };
}

/// Parse ATAPI IDENTIFY response
fn parseATAPIIdentify(channel: *Channel, drive: types.DriveInfo.DrivePosition) ?types.DriveInfo {
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

    const removable = (raw[0] & 0x80) != 0;

    logger.debug("ATAPI {s} {s}: {s} (removable: {s})", .{
        @tagName(channel.channel),
        @tagName(drive),
        model_arr[0..model_len],
        if (removable) "yes" else "no",
    });

    // Try to get capacity (may fail if no media)
    var capacity = types.Capacity.init(0, 2048);
    if (getATAPICapacity(channel, drive)) |cap| {
        capacity = cap;
    } else |_| {
        logger.debug("Could not read ATAPI capacity (no media?)", .{});
    }

    return types.DriveInfo{
        .drive_type = .ATAPI,
        .channel = channel.channel,
        .drive = drive,
        .model = model_arr,
        .capacity = capacity,
        .removable = removable,
    };
}

/// Get ATAPI drive capacity
fn getATAPICapacity(channel: *Channel, drive: types.DriveInfo.DrivePosition) !types.Capacity {
    const select: u8 = if (drive == .Master) 0xA0 else 0xB0;
    cpu.outb(channel.base + constants.ATA.REG_DEVICE, select);
    cpu.io_wait();

    _ = try common.waitForReadyPolling(channel.base, 1000);

    // Configure for PACKET command
    cpu.outb(channel.base + constants.ATA.REG_FEATURES, 0x00);
    cpu.outb(channel.base + constants.ATA.REG_LBA_MID, 0x08);
    cpu.outb(channel.base + constants.ATA.REG_LBA_HIGH, 0x00);

    // Send PACKET command
    cpu.outb(channel.base + constants.ATA.REG_COMMAND, constants.ATA.CMD_PACKET);

    // Wait for DRQ
    const status = try common.waitForDataPolling(channel.base, 1000);
    if (status & constants.ATA.STATUS_ERROR != 0) {
        return error.ReadError;
    }

    // Send READ CAPACITY packet
    var packet: [constants.ATAPI.PACKET_SIZE]u8 = .{0} ** constants.ATAPI.PACKET_SIZE;
    packet[0] = constants.ATAPI.CMD_READ_CAPACITY;

    // Send packet (6 words)
    for (0..6) |i| {
        const low = packet[i * 2];
        const high = if (i * 2 + 1 < packet.len) packet[i * 2 + 1] else 0;
        const word: u16 = (@as(u16, high) << 8) | low;
        cpu.outw(channel.base + constants.ATA.REG_DATA, word);
    }

    // Wait for data
    _ = try common.waitForDataPolling(channel.base, 1000);

    // Read response (8 bytes)
    var response: [8]u8 = undefined;
    for (0..4) |i| {
        const word = cpu.inw(channel.base + constants.ATA.REG_DATA);
        response[i * 2] = @truncate(word);
        response[i * 2 + 1] = @truncate(word >> 8);
    }

    // Parse response
    const last_lba = (@as(u32, response[0]) << 24) |
        (@as(u32, response[1]) << 16) |
        (@as(u32, response[2]) << 8) |
        response[3];

    const block_size = (@as(u32, response[4]) << 24) |
        (@as(u32, response[5]) << 16) |
        (@as(u32, response[6]) << 8) |
        response[7];

    return types.Capacity.init(last_lba + 1, block_size);
}
