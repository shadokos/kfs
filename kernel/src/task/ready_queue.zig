const std = @import("std");
const scheduler = @import("scheduler.zig");
const TaskDescriptor = @import("task.zig").TaskDescriptor;

const Queue = std.DoublyLinkedList;
pub const Node = Queue.Node;

// QueueNode data is a bool.
// It is used to check efficiently if a task is already in the ready_queue when adding it, or even to avoid
// removing it twice (which would break the DoublyLinkedList len)
// If we wanna save some memory, we could set the data type to void (as @SizeOf(void) == 0), but then we would have
// to do some linear search to perform our checks.
pub const QueueNode = struct {
    node: std.DoublyLinkedList.Node = .{},
    data: bool,
};

pub var ready_queue = Queue{};

fn unlink(node: *Queue.Node) void {
    ready_queue.remove(node);
    node.prev = null;
    node.next = null;
}

pub fn push(new_node: *TaskDescriptor) void {
    scheduler.enter_critical();
    defer scheduler.exit_critical();

    new_node.state = .Ready;

    // For performance reasons, the idle task should never be in the ready_queue.
    // The scheduler will switch to the idle task only if there is no task to run.
    if (new_node.pid == 0) return;

    if (new_node.rq_node.data == false) {
        ready_queue.append(&new_node.rq_node.node);
        new_node.rq_node.data = true;
    }
}

pub fn pop() ?*Queue.Node {
    scheduler.enter_critical();
    defer scheduler.exit_critical();

    const node = ready_queue.first orelse return null;
    const queue_node_data: *QueueNode = @fieldParentPtr("node", node);
    unlink(node);
    queue_node_data.data = false;
    return node;
}

pub fn remove(t: *TaskDescriptor) void {
    scheduler.enter_critical();
    defer scheduler.exit_critical();

    if (t.rq_node.data == false) return;

    unlink(&t.rq_node.node);
    t.rq_node.data = false;
}

pub fn init() void {
    @import("task.zig").add_on_terminate_callback(remove) catch |err| switch (err) {
        inline else => |e| @panic("ready_queue: Failed to register remove task callback: " ++ @errorName(e)),
    };
}
