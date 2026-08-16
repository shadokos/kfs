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

pub fn usleep(micro: u64) !void {
    scheduler.enter_critical();
    defer scheduler.exit_critical();

    const t = scheduler.get_current_task();

    const wake_up = timer.schedule_event(timer.Event{
        .timestamp = timer.get_utime_since_boot() + micro,
        .callback = unblock_task,
        .task = t,
    }) catch return error.ENOMEM;
    // A sleep cut short by a signal has no use for its wake up any more, and
    // leaving it behind is what lets a stopped task be made runnable again by
    // the sleep it was in when it was stopped.
    defer timer.remove_by_id(wake_up);

    ready_queue.remove(t);
    t.state = .Blocked;

    scheduler.schedule();
}

pub fn sleep(millis: u64) !void {
    return usleep(millis * 1000);
}
