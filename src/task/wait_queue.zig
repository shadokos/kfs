const TaskDescriptor = @import("task.zig").TaskDescriptor;
const scheduler = @import("scheduler.zig");
const ready_queue = @import("ready_queue.zig");

const Queue = @import("ft").DoublyLinkedList(*TaskDescriptor);
const Node = Queue.Node;

const allocator = @import("../memory.zig").smallAlloc.allocator();

pub fn WaitQueue(block_callback: fn (*TaskDescriptor) void, unblock_callback: fn (*TaskDescriptor) bool) type {
    return struct {
        const Self = @This();

        queue: Queue = .{},

        pub fn block(self: *Self, task: *TaskDescriptor) void {
            scheduler.lock();
            defer scheduler.unlock();

            const node: *Node = allocator.create(Node) catch @panic("wq.block");
            node.data = task;
            self.queue.append(node);
            block_callback(task);
        }

        pub fn try_unblock(self: *Self) void {
            scheduler.lock();
            defer scheduler.unlock();

            var node = self.queue.first;
            while (node) |n| {
                const task = n.data;
                const next = n.next;
                if (unblock_callback(task)) {
                    ready_queue.append(task);
                    self.queue.remove(n);
                    allocator.destroy(n);
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
