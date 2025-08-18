const std = @import("std");
const ArrayList = std.ArrayList;
const ArrayListAligned = std.ArrayListAligned;
const logger = std.log.scoped(.ide_controller);

const types = @import("types.zig");
const Channel = @import("channel.zig");
const discovery = @import("discovery.zig");

const allocator = @import("../../memory.zig").smallAlloc.allocator();

// === GLOBAL STORAGE ===

var controllers = ArrayList(discovery.PCIControllerInfo).init(allocator);
var drives = ArrayList(types.DriveInfo).init(allocator);
var channels = ArrayListAligned(Channel, 4).init(allocator);

// === PUBLIC INTERFACE ===

/// Get drive information by index
pub fn getDriveInfo(drive_idx: usize) ?types.DriveInfo {
    if (drive_idx >= drives.items.len) return null;
    return drives.items[drive_idx];
}

/// Get total number of drives
pub fn getDriveCount() usize {
    return drives.items.len;
}

/// Get channel by type
pub fn getChannel(channel_type: types.DriveInfo.ChannelType) ?*Channel {
    for (channels.items) |*ch| {
        if (ch.channel == channel_type) return ch;
    }
    return null;
}

/// List all detected drives
pub fn listDrives() void {
    logger.debug("=== Detected drives ===", .{});
    for (drives.items, 0..) |drive, i| {
        const model_len = blk: {
            for (drive.model, 0..) |c, idx| {
                if (c == 0) break :blk idx;
            }
            break :blk drive.model.len;
        };

        if (!std.log.logEnabled(.debug, .ide_controller)) continue;

        logger.debug("Drive {}: {s} {s} {s} - {s}", .{
            i,
            @tagName(drive.channel),
            @tagName(drive.drive),
            drive.drive_type.toString(),
            drive.model[0..model_len],
        });

        logger.debug("  Capacity: {} sectors of {} bytes", .{
            drive.capacity.sectors,
            drive.capacity.sector_size,
        });
    }
}

// === PRIVATE FUNCTIONS ===

/// Setup channels from discovered controllers
fn setupChannels() !void {
    for (controllers.items) |ctrl_info| {
        const device = ctrl_info.pci_device;
        const interface = ctrl_info.interface;

        var primary_base: u16 = 0x1F0;
        var primary_ctrl: u16 = 0x3F6;
        var secondary_base: u16 = 0x170;
        var secondary_ctrl: u16 = 0x376;
        var bm_base: u16 = 0;

        // Use PCI BAR addresses if in native mode
        if (interface.isPCINative()) {
            primary_base = @truncate(device.bars[0] & 0xFFFC);
            primary_ctrl = @truncate(device.bars[1] & 0xFFFC);
            secondary_base = @truncate(device.bars[2] & 0xFFFC);
            secondary_ctrl = @truncate(device.bars[3] & 0xFFFC);
        }

        // Get bus master base address
        if (device.bars[4] != 0) {
            bm_base = @truncate(device.bars[4] & 0xFFFC);
        }

        // Create channels
        if (primary_base != 0) {
            try channels.append(Channel{
                .base = primary_base,
                .ctrl = primary_ctrl,
                .bm_base = bm_base,
                .channel = .Primary,
                .irq = if (interface.isPCINative()) device.irq_line else 14,
                .dma_enabled = interface.supportsBusMaster() and bm_base != 0,
            });
        }

        if (secondary_base != 0) {
            try channels.append(Channel{
                .base = secondary_base,
                .ctrl = secondary_ctrl,
                .bm_base = if (bm_base != 0) bm_base + 8 else 0,
                .channel = .Secondary,
                .irq = if (interface.isPCINative()) device.irq_line else 15,
                .dma_enabled = interface.supportsBusMaster() and bm_base != 0,
            });
        }
    }
}

/// Detect all drives on all channels
fn detectAllDrives() !void {
    for (channels.items) |*channel| {
        // Detect Master drive
        const master = discovery.detectATADrive(channel, .Master) orelse
            discovery.detectATAPIDrive(channel, .Master);
        if (master) |drive_info| {
            try drives.append(drive_info);
        }

        // Detect Slave drive
        const slave = discovery.detectATADrive(channel, .Slave) orelse
            discovery.detectATAPIDrive(channel, .Slave);
        if (slave) |drive_info| {
            try drives.append(drive_info);
        }
    }

    logger.debug("Detected {} drives", .{drives.items.len});
}

/// Setup interrupt handlers
fn setupInterrupts() void {
    const interrupts = @import("../../interrupts.zig");
    const pic = @import("../../drivers/pic/pic.zig");
    const scheduler = @import("../../task/scheduler.zig");

    scheduler.enter_critical();
    defer scheduler.exit_critical();

    for (channels.items) |*channel| {
        if (channel.channel == .Primary) {
            interrupts.set_intr_gate(.PrimaryATAHardDisk, interrupts.Handler.create(primaryHandler, false));
            pic.enable_irq(.PrimaryATAHardDisk);
        } else {
            interrupts.set_intr_gate(.SecondaryATAHardDisk, interrupts.Handler.create(secondaryHandler, false));
            pic.enable_irq(.SecondaryATAHardDisk);
        }
    }
}

/// Primary channel interrupt handler
fn primaryHandler(_: @import("../../interrupts.zig").InterruptFrame) void {
    if (getChannel(.Primary)) |ch| {
        ch.processInterrupt();
    }
    @import("../../drivers/pic/pic.zig").ack(.PrimaryATAHardDisk);
}

/// Secondary channel interrupt handler
fn secondaryHandler(_: @import("../../interrupts.zig").InterruptFrame) void {
    if (getChannel(.Secondary)) |ch| {
        ch.processInterrupt();
    }
    @import("../../drivers/pic/pic.zig").ack(.SecondaryATAHardDisk);
}

// === INITIALIZATION ===

/// Initialize the IDE controller subsystem
pub fn init() !void {
    // Discover PCI controllers
    controllers = try discovery.discoverPCIControllers();

    // Setup channels
    try setupChannels();

    // Detect drives
    try detectAllDrives();

    // Setup interrupts
    setupInterrupts();
}

/// Clean up resources
pub fn deinit() void {
    controllers.deinit();
    drives.deinit();
    channels.deinit();
}
