// src/drivers/ide/request_manager.zig (Updated)
const std = @import("std");
const timer = @import("../../timer.zig");
const scheduler = @import("../../task/scheduler.zig");
const TaskDescriptor = @import("../../task/task.zig").TaskDescriptor;
const logger = std.log.scoped(.ide_request);

const types = @import("types.zig");
const controller = @import("controller.zig");
const Channel = @import("channel.zig");
const fast_io = @import("fast_io.zig");

// === REQUEST LIFECYCLE ===

/// Send a request to the IDE controller with optimized I/O
pub fn sendRequest(request: *types.Request, timeout_ms: ?usize) !void {
    const channel = controller.getChannel(request.channel) orelse return error.InvalidDrive;

    // Determine if we should use fast I/O mode
    const use_fast_io = shouldUseFastIO(request);

    if (use_fast_io) {
        // Fast path: bypass scheduler for small/critical operations
        try sendRequestFast(channel, request);
    } else {
        // Normal path: use interrupts and scheduler
        try sendRequestNormal(channel, request, timeout_ms);
    }
}

/// Fast path for small I/O operations
fn sendRequestFast(channel: *Channel, request: *types.Request) !void {
    // No need for scheduler critical section in fast mode

    if (request.is_atapi) {
        // ATAPI doesn't support fast mode yet, fallback to normal
        return sendRequestNormal(channel, request, null);
    }

    // Perform fast polling operation
    if (request.command == constants.ATA.CMD_READ_SECTORS) {
        try fast_io.fastPollRead(
            channel,
            request.drive,
            request.lba,
            request.count,
            request.buffer.read,
        );
    } else if (request.command == constants.ATA.CMD_WRITE_SECTORS) {
        try fast_io.fastPollWrite(
            channel,
            request.drive,
            request.lba,
            request.count,
            request.buffer.write,
        );
    } else {
        // Other commands fallback to normal mode
        return sendRequestNormal(channel, request, null);
    }

    request.completed = true;
}

/// Normal path using interrupts and scheduler
fn sendRequestNormal(channel: *Channel, request: *types.Request, timeout_ms: ?usize) !void {
    // Lock scheduler to avoid race conditions
    scheduler.enter_critical();
    defer scheduler.exit_critical();

    channel.current_request = request;
    defer channel.current_request = null;

    // Store timeout value in request
    request.timeout_ms = timeout_ms;

    // Send command to hardware
    try sendCommand(channel, request);

    // Schedule initial timeout
    if (timeout_ms) |_| {
        try scheduleTimeout(request);
    }

    // Wait for completion
    channel.queue.block(scheduler.get_current_task(), @ptrCast(request)) catch {
        cleanupTimeout(request);
        request.err = error.Interrupted;
        return error.Interrupted;
    };

    // Clean up any remaining timeout
    cleanupTimeout(request);

    // Check results
    if (request.timed_out) {
        channel.reset();
        return error.Timeout;
    }

    if (request.err) |err| {
        return err;
    }
}

/// Determine if we should use fast I/O mode
fn shouldUseFastIO(request: *types.Request) bool {
    const config = fast_io.getConfig();

    // Check if fast I/O is enabled
    if (config.default_mode == .Interrupt) return false;

    // ATAPI doesn't support fast mode yet
    if (request.is_atapi) return false;

    // Only READ and WRITE commands support fast mode
    if (request.command != constants.ATA.CMD_READ_SECTORS and
        request.command != constants.ATA.CMD_WRITE_SECTORS) {
        return false;
    }

    // Use fast I/O for small transfers
    if (request.count <= config.max_polling_sectors) {
        return true;
    }

    // Use fast I/O if explicitly requested (e.g., for cache operations)
    if (config.force_polling_for_cache and request.count == 1) {
        return true;
    }

    // Adaptive mode: decide based on system load
    if (config.default_mode == .Adaptive) {
        // TODO: Check system load and decide
        // For now, use fast I/O for operations <= 16 sectors
        return request.count <= 16;
    }

    return config.default_mode == .Polling;
}

/// Send command to hardware based on request type and I/O mode
fn sendCommand(channel: *Channel, request: *types.Request) !void {
    const config = fast_io.getConfig();

    // If adaptive mode and conditions are met, use adaptive functions
    if (config.default_mode == .Adaptive and !request.is_atapi) {
        if (request.command == constants.ATA.CMD_READ_SECTORS) {
            try fast_io.adaptiveRead(channel, request);
            return;
        } else if (request.command == constants.ATA.CMD_WRITE_SECTORS) {
            try fast_io.adaptiveWrite(channel, request);
            return;
        }
    }

    // Default to normal interrupt-driven mode
    if (request.is_atapi) {
        try @import("atapi.zig").sendCommandToHardware(channel, request);
    } else {
        try @import("ata.zig").sendCommandToHardware(channel, request);
    }
}

/// Schedule a timeout for the request
pub fn scheduleTimeout(request: *types.Request) !void {
    if (request.timeout_ms) |timeout| {
        const event = timer.Event{
            .timestamp = timer.get_utime_since_boot() + timeout * 1000,
            .task = scheduler.get_current_task(),
            .callback = timeoutCallback,
            .data = @alignCast(@ptrCast(request)),
        };
        request.timeout_event_id = try timer.schedule_event(event);
    }
}

/// Clean up timeout if it exists
fn cleanupTimeout(request: *types.Request) void {
    if (request.timeout_event_id) |id| {
        timer.remove_by_id(id);
        request.timeout_event_id = null;
    }
}

/// Timeout callback for IDE requests
fn timeoutCallback(_: *TaskDescriptor, data: *usize) void {
    const request: *types.Request = @alignCast(@ptrCast(data));
    const channel = controller.getChannel(request.channel) orelse return;

    logger.warn("IDE request timeout: {s} {s} (command: 0x{X}, sector: {}/{})", .{
        @tagName(request.channel),
        @tagName(request.drive),
        request.command,
        request.current_sector,
        request.count,
    });

    if (!request.completed) {
        request.timed_out = true;
        request.err = error.Timeout;
        request.timeout_event_id = null;
        channel.queue.try_unblock();
    }
}

const constants = @import("constants.zig");