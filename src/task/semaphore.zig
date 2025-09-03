const task = @import("task.zig");
const scheduler = @import("scheduler.zig");
const wait_queue = @import("wait_queue.zig");

fn semaphore_predicate(t_void: *void, _: ?*void) bool {
    const t: *task.TaskDescriptor = @ptrCast(@alignCast(t_void));
    return t.state == .Ready;
}

pub fn Semaphore(max_count: u32) type {
    return struct {
        const Self = @This();

        count: u32 = 0,
        max_count: u32 = max_count,
        queue: wait_queue.WaitQueue(.{
            .predicate = semaphore_predicate,
        }) = .{},

        pub inline fn acquire(self: *Self) void {
            scheduler.enter_critical();
            defer scheduler.exit_critical();

            if (self.count < self.max_count) {
                self.count += 1;
            } else {
                if (!scheduler.is_initialized()) @panic("Max count reached for a semaphore during early boot stage");
                self.queue.block_no_int(scheduler.get_current_task(), null);
                scheduler.schedule();
            }
        }

        pub inline fn release(self: *Self) void {
            scheduler.enter_critical();
            defer scheduler.exit_critical();

            if (self.queue.queue.first) |first| {
                const wq_node: *wait_queue.WaitQueueNode = @alignCast(@fieldParentPtr("node", first));
                const _t: *task.TaskDescriptor = @alignCast(@fieldParentPtr("wq_node", wq_node));
                _t.state = .Ready;
                self.queue.try_unblock();
            } else {
                if (self.count == 0) @panic("Trying to release a unacquired semaphore");
                self.count -= 1;
            }
        }
    };
}

pub const Mutex = Semaphore(1);
