const task = @import("task.zig");
const scheduler = @import("scheduler.zig");
const ready_queue = @import("ready_queue.zig");
const timer = @import("../timer.zig");

fn unblock_task(t: *task.TaskDescriptor, _: *usize) void {
    ready_queue.push(t);
}

pub fn usleep(micro: u64) !void {
    scheduler.lock();
    defer scheduler.unlock();

    const t = scheduler.get_current_task();

    _ = timer.schedule_event(timer.Event{
        .timestamp = timer.get_utime_since_boot() + micro,
        .callback = unblock_task,
        .task = t,
    }) catch return error.ENOMEM;

    ready_queue.remove(t);
    t.state = .Blocked;

    scheduler.schedule();
}

pub fn sleep(millis: u64) !void {
    return usleep(millis * 1000);
}
