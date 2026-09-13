const std = @import("std");
const task = @import("task.zig");
const task_set = @import("task_set.zig");
const ready_queue = @import("ready_queue.zig");

var current_task: *task.TaskDescriptor = undefined;
var idle_task: ?*task.TaskDescriptor = null;

pub var lock_depth: u32 = 0;

pub inline fn enter_critical() void {
    @import("../cpu.zig").disable_interrupts();
    lock_depth += 1;
}

pub inline fn exit_critical() void {
    lock_depth -= if (lock_depth > 0) 1 else @panic("Trying to unlock unlocked scheduler");
    if (lock_depth == 0) @import("../cpu.zig").enable_interrupts();
}

pub fn init(new_task: *task.TaskDescriptor) void {
    @This().enter_critical();
    defer @This().exit_critical();

    idle_task = new_task;
    new_task.state = .Running;
    current_task = new_task;
}

pub fn is_initialized() bool {
    return idle_task != null;
}

fn pick_next() ?*task.TaskDescriptor {
    if (ready_queue.pop()) |node| {
        const rq_node: *ready_queue.QueueNode = @alignCast(@fieldParentPtr("node", node));
        return @alignCast(@fieldParentPtr("rq_node", rq_node));
    }
    if (current_task.state != .Running and
        current_task.state != .Ready and
        current_task != idle_task)
        return idle_task;
    return null;
}

pub fn schedule() void {
    if (!is_initialized()) return;

    @This().enter_critical();
    defer @This().exit_critical();

    const prev = current_task;
    const next = pick_next() orelse return;

    if (prev.state == .Running) ready_queue.push(prev);

    next.state = .Running;
    current_task = next;
    task.switch_to_task(prev, next);
}

pub export fn checkpoint() void {
    @This().enter_critical();
    defer @This().exit_critical();

    task.save_context(current_task);
}

pub fn take_over(new_task: *task.TaskDescriptor) void {
    @This().enter_critical();
    defer @This().exit_critical();

    const prev = current_task;
    if (prev != new_task) {
        if (prev.state == .Running) ready_queue.push(prev);
        current_task = new_task;
    }
    new_task.state = .Running;
}

pub fn get_current_task() *task.TaskDescriptor {
    return current_task;
}
