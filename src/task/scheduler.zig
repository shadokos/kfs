const ft = @import("ft");
const task = @import("task.zig");
const task_set = @import("task_set.zig");

pub var lock_count: u32 = 0;
var current_task: *task.TaskDescriptor = undefined;
var initialized: bool = false;

pub fn init(new_task: *task.TaskDescriptor) void {
    @This().lock();
    initialized = true;
    current_task = new_task;
    current_task.next = new_task;
    current_task.prev = new_task;
    @This().unlock();
}

pub inline fn lock() void {
    @import("../cpu.zig").disable_interrupts();
    lock_count += 1;
}

pub inline fn unlock() void {
    lock_count -= if (lock_count > 0) 1 else @panic("Trying to unlock unlocked scheduler");
    if (lock_count == 0) @import("../cpu.zig").enable_interrupts();
}

pub fn add_task(new_task: *task.TaskDescriptor) void {
    @This().lock();
    new_task.next = current_task.next;
    new_task.prev = current_task;
    new_task.next.prev = new_task;
    new_task.prev.next = new_task;
    @This().unlock();
}

pub fn remove_task(t: *task.TaskDescriptor) void {
    @This().lock();
    t.prev.next = t.next;
    t.next.prev = t.prev;
    @This().unlock();
}

pub fn schedule() void {
    if (!initialized) return;
    @This().lock();
    const prev = current_task;
    current_task = current_task.next;
    while (current_task.state != .Running and current_task != prev) {
        current_task = current_task.next;
    }
    if (current_task.state != .Running) {
        @panic("no task running");
    }
    task.switch_to_task(prev, current_task);
    @This().unlock();
}

pub fn checkpoint() void {
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
