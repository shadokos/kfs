const ft = @import("ft");
const task = @import("task.zig");
const task_set = @import("task_set.zig");
const ready_queue = @import("ready_queue.zig");

pub var lock_count: u32 = 0;
var current_task: *task.TaskDescriptor = undefined;
pub var initialized: bool = false;

pub inline fn lock() void {
    @import("../cpu.zig").disable_interrupts();
    lock_count += 1;
}

pub inline fn unlock() void {
    lock_count -= if (lock_count > 0) 1 else @panic("Trying to unlock unlocked scheduler");
    if (lock_count == 0) @import("../cpu.zig").enable_interrupts();
}

pub fn init(new_task: *task.TaskDescriptor) void {
    @This().lock();
    defer @This().unlock();

    initialized = true;
    new_task.state = .Running;
    current_task = new_task;
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// TEST WAIT QUEUES / SLEEPING
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
const pit = @import("../drivers/pit/pit.zig");
fn sleep_callback(t: *task.TaskDescriptor) void {
    t.state = .Sleeping;
    schedule();
}
fn wakeup_callback(t: *task.TaskDescriptor) bool {
    return pit.get_utime_since_boot() >= t.sleep_timeout;
}

var sleep_queue = @import("wait_queue.zig").WaitQueue(sleep_callback, wakeup_callback){};

// wait queue but for semarphores
fn semaphore_block_callback(t: *task.TaskDescriptor) void {
    t.state = .Blocked;
    schedule();
}
fn semaphore_unblock_callback(t: *task.TaskDescriptor) bool {
    return t.state != .Blocked;
}

const scheduler = @This();

pub fn Semaphore(max_count: u32) type {
    return struct {
        const Self = @This();

        count: u32 = 0,
        max_count: u32 = max_count,
        queue: @import("wait_queue.zig").WaitQueue(semaphore_block_callback, semaphore_unblock_callback) = .{},

        pub inline fn acquire(self: *Self) void {
            scheduler.lock();
            defer scheduler.unlock();

            if (self.count < self.max_count) {
                self.count += 1;
            } else {
                self.queue.block(current_task);
                scheduler.schedule();
            }
        }

        pub inline fn release(self: *Self) void {
            scheduler.lock();
            defer scheduler.unlock();

            if (self.queue.queue.first) |first| {
                first.data.state = .Ready;
                self.queue.try_unblock();
            } else {
                self.count -= 1;
            }
        }
    };
}

pub const Mutex = Semaphore(1);

pub fn usleep(micro: u64) void {
    @This().lock();
    defer @This().unlock();

    const t = current_task;
    t.sleep_timeout = pit.get_utime_since_boot() + micro;

    // if (t.sleep_timeout <= pit.get_utime_since_boot()) return;

    sleep_queue.block(t);
    schedule();
}

pub fn sleep(millis: u64) void {
    @This().lock();
    defer @This().unlock();

    usleep(millis * 1000);
}

pub fn schedule() void {
    if (!initialized) return;

    @This().lock();
    defer @This().unlock();

    sleep_queue.try_unblock();

    if (ready_queue.popFirst()) |node| {
        const prev = current_task;
        current_task = ready_queue.get_task_descriptor(node, "rq_node");
        task.switch_to_task(prev, current_task);
    }
}

pub export fn checkpoint() void {
    @This().lock();
    task.switch_to_task(current_task, current_task);
    @This().unlock();
}

pub inline fn set_current_task(new_task: *task.TaskDescriptor) void {
    @This().lock();
    current_task = new_task;
    @This().unlock();
}

pub fn get_current_task() *task.TaskDescriptor {
    return current_task;
}
