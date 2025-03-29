const TaskDescriptor = @import("task.zig").TaskDescriptor;
const scheduler = @import("scheduler.zig");
const ready_queue = @import("ready_queue.zig");

const Queue = @import("ft").DoublyLinkedList(?*void);

pub const Node = Queue.Node;

// todo: change *void to *TaskDescriptor when https://github.com/ziglang/zig/issues/14353 is fixed
const WaitQueueArg = struct {
    /// Callback to be called when a task is added to the wait queue.
    block_callback: ?fn (*void, ?*void) void = null,

    /// Predicate to determine if a task should be unblocked.
    predicate: fn (*void, ?*void) bool,

    /// Callback to be called when a task is unblocked.
    unblock_callback: ?fn (*void, ?*void) void = null,
};

pub fn WaitQueue(arg: WaitQueueArg) type {
    return struct {
        queue: Queue = .{},

        const Self = @This();

        pub fn block(self: *Self, task: *TaskDescriptor, data: ?*void) void {
            scheduler.lock();
            defer scheduler.unlock();
			if (arg.predicate(@alignCast(@ptrCast(task)), data))
				return;

            const node: *Node = &task.wq_node;

            node.data = data;
            self.queue.append(node);
            if (arg.block_callback) |callback| callback(@alignCast(@ptrCast(task)), node.data);
            task.state = .Blocked;
            scheduler.schedule();
        }

        pub fn try_unblock(self: *Self) void {
            scheduler.lock();
            defer scheduler.unlock();

            var node = self.queue.first;
            while (node) |n| {
                const task: *TaskDescriptor = @alignCast(@fieldParentPtr("wq_node", n));
                const next = n.next;
                if (arg.predicate(@alignCast(@ptrCast(task)), n.data)) {
                    ready_queue.push(task);
                    self.queue.remove(n);
                    if (arg.unblock_callback) |callback| callback(@alignCast(@ptrCast(task)), n.data);
                }
                node = next;
            }
        }
    };
}
