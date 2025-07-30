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

const sleep_timer = @import("sleep_timer.zig");
const tsc = @import("../cpu/tsc.zig");

// pub fn usleep(micro: u64) !void {
//     scheduler.lock();
//     defer scheduler.unlock();
//
//     const t = scheduler.get_current_task();
//     const wake_time = tsc.get_time_ns() + (micro * 1000);
//
//     // Alloue un nœud pour la sleep queue (depuis un pool)
//     t.sleep_node = sleep_timer.SleepNode{
//         .wake_time = wake_time,
//     };
//
//     // Insère dans la queue triée
//     apic_timer.sleep_queue.insert(&t.sleep_node);
//
//     // Reprogramme le timer si nécessaire
//     apic_timer.schedule_next_wakeup();
//
//     // Bloque la tâche
//     t.state = .Blocked;
//     scheduler.schedule();
// }

// pub fn usleep(micro: u64) !void {
//     scheduler.lock();
//     defer scheduler.unlock();
//
//     const t = scheduler.get_current_task();
//     var sleep_timeout: u64 = apic_timer.get_utime_since_boot() + micro;
//
//     try sleep_queue.block(t, @ptrCast(&sleep_timeout));
// }

// src/task/sleep.zig
pub fn usleep(micro: u64) !void {
    scheduler.lock();
    defer scheduler.unlock();

    const t = scheduler.get_current_task();
    var wake_time = tsc.get_time_ns() + (micro * 1000);

    // Applique la coalescence si le délai est court
    const tolerance_ns: u64 = if (micro < 1000)
        1_000_000 // 100µs de tolérance pour les courts délais
    else
        1_000_000; // 1ms de tolérance pour les longs délais

    wake_time = apic_timer.coalesce_wakeups(wake_time, tolerance_ns);

    // Alloue un nœud pour la sleep queue
    t.sleep_node = sleep_timer.SleepNode{
        .wake_time = wake_time,
    };

    // Insère dans la queue triée
    apic_timer.sleep_queue.insert(&t.sleep_node);

    // Reprogramme le timer si nécessaire
    apic_timer.schedule_next_wakeup();

    // Bloque la tâche
    t.state = .Blocked;
    scheduler.schedule();
}

pub fn sleep(millis: u64) !void {
    scheduler.lock();
    defer scheduler.unlock();

    return usleep(millis * 1000);
}
