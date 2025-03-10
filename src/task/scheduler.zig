const ft = @import("ft");
const task = @import("task.zig");
const task_set = @import("task_set.zig");
const ready_queue = @import("ready_queue.zig");

var current_task: *task.TaskDescriptor = undefined;
var initialized: bool = false;

pub var lock_count: u32 = 0;

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

pub fn is_initialized() bool {
    return initialized;
}

pub fn schedule() void {
    if (!initialized) return;

    @This().lock();
    defer @This().unlock();

    @import("sleep.zig").try_unblock_sleeping_task();

    if (ready_queue.pop()) |node| {
        const prev = current_task;
        current_task = @alignCast(@fieldParentPtr("rq_node", node));
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
