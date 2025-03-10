const task = @import("task.zig");
const pit = @import("../drivers/pit/pit.zig");
const scheduler = @import("scheduler.zig");

fn sleep_callback(t: *task.TaskDescriptor) void {
    t.state = .Sleeping;
    scheduler.schedule();
}

fn sleep_predicate(t: *task.TaskDescriptor) bool {
    return t.state == .Sleeping and pit.get_utime_since_boot() >= t.sleep_timeout;
}

var sleep_queue = @import("wait_queue.zig").WaitQueue(.{
    .block_callback = sleep_callback,
    .predicate = sleep_predicate,
}){};

pub fn try_unblock_sleeping_task() void {
    sleep_queue.try_unblock();
}

pub fn usleep(micro: u64) void {
    scheduler.lock();
    defer scheduler.unlock();

    const t = scheduler.get_current_task();
    t.sleep_timeout = pit.get_utime_since_boot() + micro;

    sleep_queue.block(t);
    scheduler.schedule();
}

pub fn sleep(millis: u64) void {
    scheduler.lock();
    defer scheduler.unlock();

    usleep(millis * 1000);
}
