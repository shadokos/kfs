const std = @import("std");
const cpu = @import("../../cpu.zig");
const timer = @import("../../timer.zig");
const scheduler = @import("../../task/scheduler.zig");
const wait_queue = @import("../../task/wait_queue.zig");
const Mutex = @import("../../task/semaphore.zig").Mutex;
const ide = @import("ide.zig");
const constants = @import("constants.zig");
const types = @import("types.zig");
const common = @import("common.zig");

const Allocator = std.mem.Allocator;
const logger = std.log.scoped(.IDE_Channel);

const pci = @import("../pci/pci.zig");

pub const ChannelType = enum { Primary, Secondary };
pub const DrivePosition = enum { Master, Slave };

base: u16,
ctrl: u16,
channel_type: ChannelType,
irq: u8,
mutex: Mutex = .{},

const Self = @This();

pub fn reset(self: *Self) void {
    cpu.outb(self.ctrl, 0x04);
    for (0..100) |_| cpu.io_wait();

    cpu.outb(self.ctrl, 0x00);
    for (0..1000) |_| cpu.io_wait();

    _ = cpu.inb(self.base + constants.ATA.REG_STATUS);
    _ = cpu.inb(self.base + constants.ATA.REG_ERROR_READ);
}

/// Retrieves every channel for a given IDE interface.
pub fn get_channels(allocator: Allocator, controller: *const pci.PCIDevice) ?[]Self {
    var channels = std.ArrayListAligned(Self, 4).init(allocator);
    defer channels.deinit();

    const interface = controller.getIDEInterface() orelse return null;

    // Default values for legacy IDE controllers
    var primary_base: u16 = 0x1F0;
    var primary_ctrl: u16 = 0x3F6;
    var secondary_base: u16 = 0x170;
    var secondary_ctrl: u16 = 0x376;

    if (interface.isPCINative()) {
        primary_base = @truncate(controller.bars[0] & 0xFFFC);
        primary_ctrl = @truncate(controller.bars[1] & 0xFFFC);
        secondary_base = @truncate(controller.bars[2] & 0xFFFC);
        secondary_ctrl = @truncate(controller.bars[3] & 0xFFFC);
    }
    if (primary_base != 0) {
        channels.append(Self{
            .base = primary_base,
            .ctrl = primary_ctrl,
            .channel_type = .Primary,
            .irq = if (interface.isPCINative()) controller.irq_line else 14,
        }) catch return null;
    }
    if (secondary_base != 0) {
        channels.append(Self{
            .base = secondary_base,
            .ctrl = secondary_ctrl,
            .channel_type = .Secondary,
            .irq = if (interface.isPCINative()) controller.irq_line else 15,
        }) catch return null;
    }

    return channels.toOwnedSlice() catch null;
}

/// Retrieves every channel for a every IDE interface.
pub fn get_all_channels(allocator: Allocator) ?[]Self {
    var list = std.ArrayList(Self).init(allocator);
    defer list.deinit();

    for (ide.interfaces) |controller| {
        const chans = get_channels(allocator, &controller);
        if (chans == null or chans.?.len == 0) {
            logger.warn("0x{x}: No channels found for interface", .{controller.device_id});
            continue;
        }
        defer allocator.free(chans.?);
        list.appendSlice(chans.?) catch |err| {
            logger.warn("0x{x}: Failed to retrieve channels for : {s}", .{
                controller.device_id,
                @errorName(err),
            });
            continue;
        };
        controller.enableDevice();
    }
    return list.toOwnedSlice() catch null;
}
