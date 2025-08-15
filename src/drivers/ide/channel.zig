const std = @import("std");
const cpu = @import("../../cpu.zig");
const timer = @import("../../timer.zig");
const scheduler = @import("../../task/scheduler.zig");
const wait_queue = @import("../../task/wait_queue.zig");
const Mutex = @import("../../task/semaphore.zig").Mutex;
const constants = @import("constants.zig");
const types = @import("types.zig");
const common = @import("common.zig");

pub const ChannelType = enum { Primary, Secondary };
pub const DrivePosition = enum { Master, Slave };

base: u16,
ctrl: u16,
channel_type: ChannelType,
irq: u8,
// queue: wait_queue.WaitQueue(.{ .predicate = request_predicate }) = .{},
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
