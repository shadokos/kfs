const TaskDescriptor = @import("task.zig").TaskDescriptor;
const scheduler = @import("scheduler.zig");
const ready_queue = @import("ready_queue.zig");

const Queue = @import("ft").DoublyLinkedList(*TaskDescriptor);
const Node = Queue.Node;

const allocator = @import("../memory.zig").smallAlloc.allocator();

const WaitQueueArg = struct {
    /// Callback to be called when a task is added to the wait queue.
    block_callback: ?fn (*TaskDescriptor) void = null,

    /// Predicate to determine if a task should be unblocked.
    predicate: fn (*TaskDescriptor) bool,

    /// Callback to be called when a task is unblocked.
    unblock_callback: ?fn (*TaskDescriptor) void = null,
};

pub fn WaitQueue(arg: WaitQueueArg) type {
    return struct {
        const Self = @This();

        queue: Queue = .{},

        pub fn block(self: *Self, task: *TaskDescriptor) void {
            scheduler.lock();
            defer scheduler.unlock();

            const node: *Node = allocator.create(Node) catch @panic("wq.block");
            node.data = task;
            self.queue.append(node);
            if (arg.block_callback) |callback| callback(task);
        }

        pub fn try_unblock(self: *Self) void {
            scheduler.lock();
            defer scheduler.unlock();

            var node = self.queue.first;
            while (node) |n| {
                const task = n.data;
                const next = n.next;
                if (arg.predicate(task)) {
                    ready_queue.append(task);
                    self.queue.remove(n);
                    allocator.destroy(n);
                    if (arg.unblock_callback) |callback| callback(task);
                }
                node = next;
            }
        }

        // // Remove and return the first node in the list.
        // pub fn popFirst(self: *Self) ?*TaskDescriptor {
        //     scheduler.lock();
        //     defer scheduler.unlock();

        //     return self.queue.popFirst();
        // }

        // // Insert a new node at the beginning of the list.
        // pub fn prepend(self: *Self, task: *TaskDescriptor) void {
        //     scheduler.lock();
        //     defer scheduler.unlock();

        //     self.queue.prepend(task);
        // }

        // // Remove a node from the list.
        // pub fn remove(self: *Self, node: *TaskDescriptor) void {
        //     scheduler.lock();
        //     defer scheduler.unlock();

        //     self.queue.remove(node);
        // }
    };
}
