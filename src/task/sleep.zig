const task = @import("task.zig");
const apic_timer = @import("../drivers/apic/timer.zig");
const scheduler = @import("scheduler.zig");

fn sleep_predicate(_: *void, sleep_timeout_ptr: ?*void) bool {
    const sleep_timeout: u64 = @as(*u64, @alignCast(@ptrCast(sleep_timeout_ptr.?))).*;
    return apic_timer.get_utime_since_boot() >= sleep_timeout;
}

var sleep_queue = @import("wait_queue.zig").WaitQueue(.{
    .predicate = sleep_predicate,
}){};

pub fn try_unblock_sleeping_task() void {
    sleep_queue.try_unblock();
}

pub fn usleep(micro: u64) !void {
    scheduler.lock();
    defer scheduler.unlock();

    const t = scheduler.get_current_task();
    var sleep_timeout: u64 = apic_timer.get_utime_since_boot() + micro;

    try sleep_queue.block(t, @ptrCast(&sleep_timeout));
}

pub fn sleep(millis: u64) !void {
    scheduler.lock();
    defer scheduler.unlock();

    return usleep(millis * 1000);
}
