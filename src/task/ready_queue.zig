const std = @import("std");
const scheduler = @import("scheduler.zig");
const TaskDescriptor = @import("task.zig").TaskDescriptor;

// Queue.Node.Data is a bool.
// It is used to check efficiently if a task is already in the ready_queue when adding it, or even to avoid
// removing it twice (which would break the DoublyLinkedList len)
// If we wanna save some memory, we could set the data type to void (as @SizeOf(void) == 0), but then we would have
// to do some linear search to perform our checks.
const Queue = std.DoublyLinkedList(bool);

pub const Node = Queue.Node;

pub var ready_queue = Queue{};

pub fn push(new_node: *TaskDescriptor) void {
    scheduler.lock();
    defer scheduler.unlock();

    // For performance reasons, the idle task should never be in the ready_queue.
    // The scheduler will switch to the idle task only if there is no task to run.
    if (new_node.pid == 0) return;

    if (new_node.rq_node.data == false)
        ready_queue.append(&new_node.rq_node);

    new_node.rq_node.data = true;
    new_node.state = .Ready;
}

pub fn pop() ?*Queue.Node {
    scheduler.lock();
    defer scheduler.unlock();

    const node = ready_queue.popFirst();
    if (node) |n| n.data = false;
    return node;
}

pub fn remove(t: *TaskDescriptor) void {
    scheduler.lock();
    defer scheduler.unlock();

    if (t.rq_node.data == false) return;

    ready_queue.remove(&t.rq_node);
    t.rq_node.data = false;

    // Should we set the task to a different state here ???
    // Not sure, as this method is called during an exit, right after setting it to .Zombie state.
    // TODO: Maybe we should discuss it together.
}
