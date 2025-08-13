const std = @import("std");
const timer = @import("../../timer.zig");
const scheduler = @import("../../task/scheduler.zig");
const TaskDescriptor = @import("../../task/task.zig").TaskDescriptor;
const logger = std.log.scoped(.ide_request);

const types = @import("types.zig");
const controller = @import("controller.zig");
const Channel = @import("channel.zig");

// === REQUEST LIFECYCLE ===

/// Send a request to the IDE controller and wait for completion
pub fn sendRequest(request: *types.Request, timeout_ms: ?usize) !void {
    const channel = controller.getChannel(request.channel) orelse return error.InvalidDrive;

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

/// Send command to hardware based on request type
fn sendCommand(channel: *Channel, request: *types.Request) !void {
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
