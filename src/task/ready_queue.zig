const ft = @import("ft");
const scheduler = @import("scheduler.zig");
const TaskDescriptor = @import("task.zig").TaskDescriptor;

const Self = @This();

// Queue.Node.Data is a pointer to the ready_queue (here defined as ?*usize to avoid circular dependencies).
// It is used to check efficiently if a task is already in the ready_queue when adding it, or even to avoid
// removing it twice (which would break the DoublyLinkedList len)
// If we wanna save some memor, we could set the data type to void (@SizeOf(void) == 0), but then we would have
// to do some linear search to perform our checks.
const Queue = ft.DoublyLinkedList(?*usize);

pub const Node = Queue.Node;

pub var ready_queue = Queue{};

pub fn append(new_node: *TaskDescriptor) void {
    scheduler.lock();
    defer scheduler.unlock();

    defer {
        new_node.rq_node.data = @ptrCast(&ready_queue);
        new_node.state = .Ready;
    }

    if (new_node.rq_node.data) |_| return;
    ready_queue.append(&new_node.rq_node);
}

pub fn prepend(new_node: *TaskDescriptor) void {
    scheduler.lock();
    defer scheduler.unlock();

    if (new_node.rq_node.data) |_| ft.log.err(
        "Trying to prepend a task that is already in the ReadyQueue (rq: {*}, pid: {}, rq_node.data: {*})",
        .{ &ready_queue, new_node.pid, new_node.rq_node.data },
    );

    new_node.rq_node.data = @ptrCast(&ready_queue);
    ready_queue.prepend(&new_node.rq_node);
    new_node.state = .Ready;
}

pub fn remove(t: *TaskDescriptor) void {
    scheduler.lock();
    defer scheduler.unlock();

    if (t.rq_node.data == null) return;

    ready_queue.remove(&t.rq_node);
    t.rq_node.data = null;

    // Should we set the task to a different state here ???
    // Not sure, as this method is called during an exit, right after setting it to .Zombie state.
    // TODO: Maybe we should discuss it together.
}

pub fn popFirst() ?*Queue.Node {
    scheduler.lock();
    defer scheduler.unlock();

    const node = ready_queue.popFirst();
    if (node) |n| n.data = null;
    return node;
}

pub fn pop() ?*Queue.Node {
    scheduler.lock();
    defer scheduler.unlock();

    const node = ready_queue.pop();
    if (node) |n| n.data = null;
    return node;
}

pub fn debug_ready_queue(message: []const u8) void {
    ft.log.info("ReadyQueue: {}", .{message});
    var node = ready_queue.head;
    while (node) {
        const td = scheduler.test_get_td(node, "rq_node");
        ft.log.info("pid: {}, state: {}", .{ td.pid, td.state });
        node = node.next;
    }
}

pub fn get_task_descriptor(node: *Queue.Node, comptime fieldname: []const u8) *TaskDescriptor {
    const offset = @offsetOf(TaskDescriptor, fieldname);
    return @ptrFromInt(@as(usize, @intFromPtr(node)) - offset);
}
