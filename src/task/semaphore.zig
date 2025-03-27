const task = @import("task.zig");
const scheduler = @import("scheduler.zig");

fn semaphore_block_callback(t: *task.TaskDescriptor) void {
    t.state = .Blocked;
    scheduler.schedule();
}

fn semaphore_predicate(t: *task.TaskDescriptor) bool {
    return t.state == .Ready;
}

pub fn Semaphore(max_count: u32) type {
    return struct {
        const Self = @This();

        count: u32 = 0,
        max_count: u32 = max_count,
        queue: @import("wait_queue.zig").WaitQueue(.{
            .block_callback = semaphore_block_callback,
            .predicate = semaphore_predicate,
        }) = .{},

        pub inline fn acquire(self: *Self) void {
            scheduler.lock();
            defer scheduler.unlock();

            if (self.count < self.max_count) {
                self.count += 1;
            } else {
                if (!scheduler.is_initialized()) @panic("Max count reached for a semaphore during early boot stage");
                self.queue.block(scheduler.get_current_task());
                scheduler.schedule();
            }
        }

        pub inline fn release(self: *Self) void {
            scheduler.lock();
            defer scheduler.unlock();

            if (self.queue.queue.first) |first| {
                const _t: *task.TaskDescriptor = @alignCast(@fieldParentPtr("wq_node", first));
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
