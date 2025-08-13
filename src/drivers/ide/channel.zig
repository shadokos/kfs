const std = @import("std");
const cpu = @import("../../cpu.zig");
const timer = @import("../../timer.zig");
const scheduler = @import("../../task/scheduler.zig");
const wait_queue = @import("../../task/wait_queue.zig");
const Mutex = @import("../../task/semaphore.zig").Mutex;
const logger = std.log.scoped(.ide_channel);

const constants = @import("constants.zig");
const types = @import("types.zig");
const common = @import("common.zig");
const request_manager = @import("request_manager.zig");

// === WAIT QUEUE PREDICATE ===

fn request_predicate(_: *void, data: ?*void) bool {
    if (data == null) return false;
    const request: *types.Request = @alignCast(@ptrCast(data.?));
    return request.completed or request.timed_out or (request.err != null);
}

// === CHANNEL STRUCTURE ===

base: u16,
ctrl: u16,
bm_base: u16,
channel: types.DriveInfo.ChannelType,
irq: u8,
current_request: ?*types.Request = null,
queue: wait_queue.WaitQueue(.{
    .predicate = request_predicate,
}) = .{},
mutex: Mutex = .{},
dma_enabled: bool = false,

const Self = @This();

// === INTERRUPT HANDLING ===

/// Process interrupt for current request
pub fn processInterrupt(self: *Self) void {
    const request = self.current_request orelse return;

    // Cancel existing timeout
    if (request.timeout_event_id) |id| {
        timer.remove_by_id(id);
        request.timeout_event_id = null;
    }

    // Read status register to acknowledge interrupt
    const status = cpu.inb(self.base + constants.ATA.REG_STATUS);

    // Check for errors
    if (status & constants.ATA.STATUS_ERROR != 0) {
        request.err = common.parseATAError(self.base);
        request.completed = true;
        self.queue.try_unblock();
        return;
    }

    // Process based on command type
    if (request.is_atapi) {
        @import("atapi.zig").handleInterrupt(self, request);
    } else {
        @import("ata.zig").handleInterrupt(self, request, status);
    }

    // Schedule new timeout if needed
    if (!request.completed and request.timeout_ms != null) {
        request_manager.scheduleTimeout(request) catch {};
    }
}

/// Wait for drive ready
pub fn waitForReady(self: *Self) !u8 {
    return common.waitForReadyAsync(self.base, self.ctrl, 1000);
}

/// Wait for data ready
pub fn waitForData(self: *Self) !u8 {
    return common.waitForDataAsync(self.base, self.ctrl, 1000);
}

/// Reset the channel
pub fn reset(self: *Self) void {
    logger.debug("Resetting IDE channel", .{});

    // Software reset
    cpu.outb(self.ctrl, 0x04);
    for (0..100) |_| cpu.io_wait();

    // Cancel reset
    cpu.outb(self.ctrl, 0x00);
    for (0..1000) |_| cpu.io_wait();

    // Clear pending status
    _ = cpu.inb(self.base + constants.ATA.REG_STATUS);
    _ = cpu.inb(self.base + constants.ATA.REG_ERROR_READ);
}
