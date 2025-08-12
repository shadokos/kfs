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

// Scheduling quantum for preemption (in microseconds)
const quantum_us: u64 = 50_000; // 10 ms

var event_queue: EventQueue = undefined;

// Monotonic microseconds since boot (advanced by programmed PIT delays)
var now_us: u64 = 0;

// Number of timer interrupts seen (for compatibility)
var ticks: u64 = 0;

// The currently programmed delay and its absolute deadline
var programmed_us: u64 = 0;
var current_deadline_us: u64 = 0;

fn program_next_interrupt() void {
    var delay_us: u64 = quantum_us;

    if (event_queue.peek()) |n| {
        if (n.event.timestamp > now_us) {
            const until_event = n.event.timestamp - now_us;
            if (until_event < delay_us)
                delay_us = until_event;
        } else {
            delay_us = 1;
        }
    }

    if (delay_us == 0) delay_us = 1;

    programmed_us = delay_us;
    current_deadline_us = now_us + delay_us;
    pit.set_timeout_us(delay_us);
}

pub fn schedule_event(event: Event) !u64 {
    const id = try event_queue.add(event);

    // If this event is earlier than the current deadline, reprogram the PIT.
    if (event.timestamp < current_deadline_us) {
        program_next_interrupt();
    }
    return id;
}

pub fn remove(t: *task.TaskDescriptor) void {
    event_queue.clear_task(t);
}

pub fn remove_by_id(id: u64) void {
    _ = event_queue.remove_by_id(id);
}

fn consume_events() void {
    var next_event: ?EventQueue.Node = event_queue.peek();
    while (next_event) |n| {
        const event = n.event;
        if (event.timestamp > now_us) break;

        _ = event_queue.remove();

        if (event.callback) |cb| {
            cb(event.task, event.data);
        }
        next_event = event_queue.peek();
    }
}

fn timer_handler(_: interrupts.InterruptFrame) void {
    const scheduler = @import("task/scheduler.zig");
    scheduler.lock();
    defer scheduler.unlock();

    ticks += 1;
    now_us += if (programmed_us != 0) programmed_us else quantum_us;

    consume_events();

    pic.ack(.Timer);

    // Schedule next interrupt (either next event or preemption quantum)
    program_next_interrupt();

    scheduler.schedule();
}

pub inline fn get_ticks() u64 {
    return ticks;
}

pub inline fn get_utime_since_boot() u64 {
    return now_us;
}

pub inline fn get_time_since_boot() u64 {
    return now_us / 1_000;
}

pub fn sleep_n_ticks(n: u64) void {
    const start = get_ticks();
    while (get_ticks() - start < n) {
        @import("cpu.zig").halt();
    }
}

pub fn busy_usleep(micro: u64) void {
    const start = now_us;
    while (now_us - start < micro) {
        @import("cpu.zig").halt();
    }
}

pub fn busy_sleep(millis: u64) void {
    busy_usleep(millis * 1_000);
}

pub fn init() void {
    event_queue = EventQueue.init();

    // Switch to dynamic one-shot ticks driven by next event or quantum.
    // Install handler and enable IRQ before programming first timeout.
    interrupts.set_intr_gate(.Timer, interrupts.Handler.create(timer_handler, false));
    pic.enable_irq(.Timer);

    // Initially program a quantum to start preemption.
    programmed_us = 0;
    current_deadline_us = 0;
    program_next_interrupt();

    @import("task/task.zig").on_terminate_callback.append(remove) catch |err| switch (err) {
        inline else => |e| @panic("timer: Failed to register remove task callback: " ++ @errorName(e)),
    };
}
