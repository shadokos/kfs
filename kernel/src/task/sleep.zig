const std = @import("std");
const task = @import("task.zig");
const scheduler = @import("scheduler.zig");
const ready_queue = @import("ready_queue.zig");
const timer = @import("../timer.zig");

fn unblock_task(t: *task.TaskDescriptor, _: *usize) void {
    // An event that outlived what scheduled it must not requeue a task that has
    // since been stopped or killed.
    if (t.state != .Blocked) return;
    ready_queue.push(t);
}

/// Sleep until an instant, not for a duration: a task stopped mid-sleep pauses
/// on this stack and waits out the rest, so time spent stopped counts.
pub fn usleep(micro: u64) !void {
    scheduler.enter_critical();
    defer scheduler.exit_critical();

    const t = scheduler.get_current_task();
    const deadline = timer.get_utime_since_boot() + micro;

    while (timer.get_utime_since_boot() < deadline) {
        const wake_up = timer.schedule_event(timer.Event{
            .timestamp = deadline,
            .callback = unblock_task,
            .task = t,
        }) catch return error.ENOMEM;

        t.state = .Blocked;
        scheduler.schedule();

        // Either it fired, or a signal got there first and it must not later.
        timer.remove_by_id(wake_up);

        switch (t.pending_disposition()) {
            .stop => t.stop_in_place(),
            .interrupt => return error.EINTR,
            .none => {},
        }
    }
}

pub fn sleep(millis: u64) !void {
    return usleep(millis * 1000);
}
