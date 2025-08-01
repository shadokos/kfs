const std = @import("std");
const TaskDescriptor = @import("task.zig").TaskDescriptor;
const scheduler = @import("scheduler.zig");
const ready_queue = @import("ready_queue.zig");
const Errno = @import("../errno.zig").Errno;

const Payload = struct {
    data: ?*void,
    queue: ?*Queue,
};

pub const WaitQueueNode = struct {
    node: std.DoublyLinkedList.Node = .{},
    data: Payload,
};

const Queue = std.DoublyLinkedList;

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
            scheduler.lock();
            defer scheduler.unlock();
            if (arg.predicate(@ptrCast(@alignCast(task)), data))
                return;

            task.wq_node.data.data = data;
            task.wq_node.data.queue = &self.queue;
            self.queue.append(&task.wq_node.node);
            if (arg.block_callback) |callback| callback(@ptrCast(@alignCast(task)), task.wq_node.data.data);
            task.state = if (interruptible) .Blocked else .BlockedUninterruptible;
            scheduler.schedule();
        }

        pub fn block(self: *Self, task: *TaskDescriptor, data: ?*void) !void {
            self.internal_block(task, true, data);
            if (!arg.predicate(@ptrCast(@alignCast(task)), data))
                return Errno.EINTR;
        }

        pub fn block_no_int(self: *Self, task: *TaskDescriptor, data: ?*void) void {
            self.internal_block(task, false, data);
        }

        pub fn try_unblock(self: *Self) void {
            scheduler.lock();
            defer scheduler.unlock();

            var node = self.queue.first;
            while (node) |n| {
                const wait_queue_node: *WaitQueueNode = @fieldParentPtr("node", n);
                const task: *TaskDescriptor = @alignCast(@fieldParentPtr("wq_node", wait_queue_node));
                const next = n.next;
                if (arg.predicate(@ptrCast(@alignCast(task)), wait_queue_node.data.data)) {
                    ready_queue.push(task);
                    self.queue.remove(n);
                    if (arg.unblock_callback) |callback|
                        callback(@ptrCast(@alignCast(task)), wait_queue_node.data.data);
                    task.wq_node.data.queue = null;
                }
                node = next;
            }
        }

        pub fn unblock_all(self: *Self) void {
            scheduler.lock();
            defer scheduler.unlock();

            var node = self.queue.first;
            while (node) |n| {
                const wait_queue_node: *WaitQueueNode = @fieldParentPtr("node", n);
                const task: *TaskDescriptor = @alignCast(@fieldParentPtr("wq_node", wait_queue_node));
                const next = n.next;
                ready_queue.push(task);
                self.queue.remove(n);
                if (arg.unblock_callback) |callback| callback(@ptrCast(@alignCast(task)), wait_queue_node.data.data);
                node = next;
            }
        }
    };
}

pub fn interrupt(task: *TaskDescriptor) void {
    scheduler.lock();
    defer scheduler.unlock();
    if (task.state != .Blocked)
        return;

    // As task/sleep.zig doesn't rely on wait_queue anymore,
    // a blocking task is not guaranteed to be in a wait queue.
    if (task.wq_node.data.queue) |q| {
        q.remove(&task.wq_node.node);
        task.wq_node.data.queue = null;
    }
    ready_queue.push(task);
}

pub fn force_remove(task: *TaskDescriptor) void {
    scheduler.lock();
    defer scheduler.unlock();
    if (task.state != .Blocked and task.state != .BlockedUninterruptible)
        return;

    // As task/sleep.zig doesn't rely on wait_queue anymore,
    // a blocking task is not guaranteed to be in a wait queue.
    if (task.wq_node.data.queue) |q| {
        q.remove(&task.wq_node.node);
        task.wq_node.data.queue = null;
    }
}

pub fn init() void {
    @import("task.zig").add_on_terminate_callback(force_remove) catch |err| switch (err) {
        inline else => |e| @panic("wait_queue: Failed to register remove task callback: " ++ @errorName(e)),
    };
}
