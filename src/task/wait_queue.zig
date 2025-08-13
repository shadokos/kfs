const TaskDescriptor = @import("task.zig").TaskDescriptor;
const scheduler = @import("scheduler.zig");
const ready_queue = @import("ready_queue.zig");
const Errno = @import("../errno.zig").Errno;

const Payload = struct {
    data: ?*void,
    queue: ?*Queue,
};

const Queue = @import("std").DoublyLinkedList(Payload);

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

        fn internal_block(self: *Self, task: *TaskDescriptor, interruptible: bool, data: ?*void) void {
            scheduler.enter_critical();
            defer scheduler.exit_critical();
            if (arg.predicate(@alignCast(@ptrCast(task)), data))
                return;

            const node: *Node = &task.wq_node;

            node.data.data = data;
            node.data.queue = &self.queue;
            self.queue.append(node);
            if (arg.block_callback) |callback| callback(@alignCast(@ptrCast(task)), node.data.data);
            task.state = if (interruptible) .Blocked else .BlockedUninterruptible;
            scheduler.schedule();
        }

        pub fn block(self: *Self, task: *TaskDescriptor, data: ?*void) !void {
            self.internal_block(task, true, data);
            if (!arg.predicate(@alignCast(@ptrCast(task)), data))
                return Errno.EINTR;
        }

        pub fn block_no_int(self: *Self, task: *TaskDescriptor, data: ?*void) void {
            self.internal_block(task, false, data);
        }

        pub fn try_unblock(self: *Self) void {
            scheduler.enter_critical();
            defer scheduler.exit_critical();

            var node = self.queue.first;
            while (node) |n| {
                const task: *TaskDescriptor = @alignCast(@fieldParentPtr("wq_node", n));
                const next = n.next;
                if (arg.predicate(@alignCast(@ptrCast(task)), n.data.data)) {
                    ready_queue.push(task);
                    self.queue.remove(n);
                    if (arg.unblock_callback) |callback| callback(@alignCast(@ptrCast(task)), n.data.data);
                    task.wq_node.data.queue = null;
                }
                node = next;
            }
        }

        pub fn unblock_all(self: *Self) void {
            scheduler.enter_critical();
            defer scheduler.exit_critical();

            var node = self.queue.first;
            while (node) |n| {
                const task: *TaskDescriptor = @alignCast(@fieldParentPtr("wq_node", n));
                const next = n.next;
                ready_queue.push(task);
                self.queue.remove(n);
                if (arg.unblock_callback) |callback| callback(@alignCast(@ptrCast(task)), n.data);
                node = next;
            }
        }
    };
}

pub fn interrupt(task: *TaskDescriptor) void {
    scheduler.enter_critical();
    defer scheduler.exit_critical();
    if (task.state != .Blocked)
        return;

    // As task/sleep.zig doesn't rely on wait_queue anymore,
    // a blocking task is not guaranteed to be in a wait queue.
    if (task.wq_node.data.queue) |q| {
        q.remove(&task.wq_node);
        task.wq_node.data.queue = null;
    }

    ready_queue.push(task);
}

pub fn force_remove(task: *TaskDescriptor) void {
    scheduler.enter_critical();
    defer scheduler.exit_critical();
    if (task.state != .Blocked and task.state != .BlockedUninterruptible)
        return;

    // As task/sleep.zig doesn't rely on wait_queue anymore,
    // a blocking task is not guaranteed to be in a wait queue.
    if (task.wq_node.data.queue) |q| {
        q.remove(&task.wq_node);
        task.wq_node.data.queue = null;
    }
}

pub fn init() void {
    @import("task.zig").on_terminate_callback.append(force_remove) catch |err| switch (err) {
        inline else => |e| @panic("wait_queue: Failed to register remove task callback: " ++ @errorName(e)),
    };
}
