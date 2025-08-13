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

pub fn schedule() void {
    if (!is_initialized()) return;

    @This().enter_critical();
    defer @This().exit_critical();

    var next_task: ?*task.TaskDescriptor = null;
    if (ready_queue.pop()) |node| {
        const rq_node: *ready_queue.QueueNode = @alignCast(@fieldParentPtr("node", node));
        next_task = @alignCast(@fieldParentPtr("rq_node", rq_node));
    } else if (current_task.state != .Running and current_task.state != .Ready and current_task != idle_task) {
        next_task = idle_task;
    }

    if (next_task) |next| {
        const prev = current_task;
        current_task = next;
        task.switch_to_task(prev, next);
    }
}

pub export fn checkpoint() void {
    @This().enter_critical();
    task.switch_to_task(current_task, current_task);
    @This().exit_critical();
}

pub inline fn set_current_task(new_task: *task.TaskDescriptor) void {
    @This().enter_critical();
    current_task = new_task;
    @This().exit_critical();
}

pub fn get_current_task() *task.TaskDescriptor {
    return current_task;
}
