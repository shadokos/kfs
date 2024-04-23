const ft = @import("../ft/ft.zig");
const task = @import("task.zig");
const task_set = @import("task_set.zig");

pub var current_task: ?*task.TaskDescriptor = null;

pub fn add_task(new_task: *task.TaskDescriptor) void {
    if (current_task) |current| {
        new_task.next = current.next;
        new_task.prev = current;
        new_task.next.prev = new_task;
        new_task.prev.next = new_task;
    } else {
        current_task = new_task;
        new_task.next = new_task;
        new_task.prev = new_task;
    }
}

pub fn schedule() void {
    if (current_task) |current| {
        current_task = current.next;
        task.switch_to_task(current, current.next);
    } else @panic("No task to schedule");
}

pub fn checkpoint() void {
    if (current_task) |current| {
        task.switch_to_task(current, current);
    } else @panic("No task");
}

pub inline fn set_current_task(new_task: *task.TaskDescriptor) void {
    current_task = new_task;
}
