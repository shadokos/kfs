const ft = @import("../ft/ft.zig");
const task = @import("task.zig");
const task_set = @import("task_set.zig");

var current_task: *task.TaskDescriptor = undefined;

pub fn add_task(new_task: *task.TaskDescriptor) void {
    new_task.next = current_task.next;
    new_task.prev = current_task;
    new_task.next.prev = new_task;
    new_task.prev.next = new_task;
}

var initialized: bool = false;

pub fn init(new_task: *task.TaskDescriptor) void {
    initialized = true;
    current_task = new_task;
    new_task.next = new_task;
    new_task.prev = new_task;
}

pub fn remove_task(t: *task.TaskDescriptor) void {
    t.prev.next = t.next;
    t.next.prev = t.prev;
}

pub fn schedule() void {
    if (!initialized) return;
    const prev = current_task;
    current_task = current_task.next;
    while (current_task.state != .Running and current_task != prev) {
        current_task = current_task.next;
    }
    if (current_task.state != .Running) {
        @panic("no task running");
    }
    task.switch_to_task(prev, current_task);
}

pub fn checkpoint() void {
    task.switch_to_task(current_task, current_task);
}

pub inline fn set_current_task(new_task: *task.TaskDescriptor) void {
    current_task = new_task;
}

pub fn get_current_task() *task.TaskDescriptor {
    return current_task;
}
