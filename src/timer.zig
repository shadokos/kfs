const task = @import("task/task.zig");
const interrupts = @import("interrupts.zig");
const pit = @import("drivers/pit/pit.zig");
const pic = @import("drivers/pic/pic.zig");

const std = @import("std");
const PriorityQueue = @import("std").PriorityQueue;
const Order = @import("std").math.Order;

pub const Event = struct {
    timestamp: u64,
    task: *task.TaskDescriptor,

    callback: ?*const fn (*task.TaskDescriptor, *usize) void,
    data: *usize = undefined,
};

pub const EventQueue = struct {
    pub const Node = struct {
        id: u64,
        event: Event,

        pub fn compare(_: void, a: @This(), b: @This()) Order {
            return std.math.order(a.event.timestamp, b.event.timestamp);
        }
    };

    const Q = PriorityQueue(Node, void, Node.compare);

    queue: Q = undefined,
    next_id: u64 = 0, // Used to generate unique event IDs if needed

    pub fn init() EventQueue {
        return .{
            .queue = Q.init(@import("memory.zig").smallAlloc.allocator(), {}),
        };
    }

    pub fn add(self: *EventQueue, event: Event) !u64 {
        const id = self.next_id;
        self.next_id += 1;
        try self.queue.add(Node{ .id = id, .event = event });
        return id;
    }

    pub fn peek(self: *EventQueue) ?Node {
        return self.queue.peek();
    }

    pub fn remove(self: *EventQueue) ?Node {
        return self.queue.removeOrNull();
    }

    pub fn clear(self: *EventQueue) void {
        self.queue.clear();
    }

    pub fn is_empty(self: *EventQueue) bool {
        return self.queue.isEmpty();
    }

    // Remove all events associated with a specific task
    pub fn clear_task(self: *EventQueue, t: *task.TaskDescriptor) void {
        var i: usize = 0;
        while (i < self.queue.items.len) {
            if (self.queue.items[i].event.task == t) {
                _ = self.queue.removeIndex(i);
            } else {
                i += 1;
            }
        }
    }

    pub fn remove_by_id(self: *EventQueue, id: u64) ?Node {
        for (self.queue.items, 0..) |node, i| {
            if (node.id == id) {
                return self.queue.removeIndex(i);
            }
        }
        return null;
    }
};

const interval: u64 = 10_000; // 10 ms in us

var event_queue: EventQueue = undefined;
var ticks: u64 = 0;

pub fn schedule_event(event: Event) !u64 {
    return event_queue.add(event);
}

pub fn remove(t: *task.TaskDescriptor) void {
    event_queue.clear_task(t);
}

pub fn remove_by_id(id: u64) void {
    _ = event_queue.remove_by_id(id);
}

fn timer_handler(_: interrupts.InterruptFrame) void {
    const scheduler = @import("task/scheduler.zig");
    scheduler.lock();
    defer scheduler.unlock();

    ticks += 1;

    var next_event: ?EventQueue.Node = event_queue.peek();
    while (next_event) |n| {
        const event = n.event;

        if (event.timestamp > get_utime_since_boot()) break;

        _ = event_queue.remove();

        if (event.callback) |cb| {
            cb(event.task, event.data);
        }
        next_event = event_queue.peek();
    }
    pic.ack(.Timer);

    scheduler.schedule();
}

pub inline fn get_ticks() u64 {
    return ticks;
}

pub inline fn get_utime_since_boot() u64 {
    return (ticks * interval);
}

pub inline fn get_time_since_boot() u64 {
    return (ticks * interval) / 1_000;
}

pub fn sleep_n_ticks(n: u64) void {
    const start = get_ticks();
    while (get_ticks() - start < n) {
        @import("cpu.zig").halt();
    }
}

pub fn busy_usleep(micro: u64) void {
    const ticks_to_sleep = micro / interval;
    sleep_n_ticks(ticks_to_sleep);
}

pub fn busy_sleep(millis: u64) void {
    const ticks_to_sleep = (millis * 1_000) / interval;
    sleep_n_ticks(ticks_to_sleep);
}

pub fn init() void {
    event_queue = EventQueue.init();

    // Initialize the PIT (100 Hz, 10 ms period)
    // interval is in microseconds
    const frequency: u32 = @truncate(1_000_000 / interval); // 100 Hz
    pit.init_channel(.Channel_0, frequency);

    interrupts.set_intr_gate(.Timer, interrupts.Handler.create(timer_handler, false));
    pic.enable_irq(.Timer);

    @import("task/task.zig").add_on_terminate_callback(remove) catch |err| switch (err) {
        inline else => |e| @panic("timer: Failed to register remove task callback: " ++ @errorName(e)),
    };
}
