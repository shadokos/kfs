const TaskDescriptor = @import("task.zig").TaskDescriptor;
const scheduler = @import("scheduler.zig");
const ready_queue = @import("ready_queue.zig");

const Queue = @import("ft").DoublyLinkedList(?*void);

pub const Node = Queue.Node;

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

            const node: *Node = &task.wq_node;
            self.queue.append(node);
            if (arg.block_callback) |callback| callback(task);
        }

        pub fn try_unblock(self: *Self) void {
            scheduler.lock();
            defer scheduler.unlock();

            var node = self.queue.first;
            while (node) |n| {
                const task: *TaskDescriptor = @alignCast(@fieldParentPtr("wq_node", n));
                const next = n.next;
                if (arg.predicate(task)) {
                    ready_queue.push(task);
                    self.queue.remove(n);
                    if (arg.unblock_callback) |callback| callback(task);
                }
                node = next;
            }
        }
    };
}
