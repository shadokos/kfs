const task = @import("../task/task.zig");
const scheduler = @import("../task/scheduler.zig");
const task_set = @import("../task/task_set.zig");
const Errno = @import("../errno.zig").Errno;
const interrupts = @import("../interrupts.zig");
const tty = @import("../tty/tty.zig");

const paging = @import("../memory/paging.zig");
const mapping = @import("../memory/mapping.zig");

pub const Id = 7;

fn exec_child(any_frame: anytype) u8 {
    var frame: interrupts.InterruptFrame = any_frame;
    if (scheduler.get_current_task().vm) |vm|
        vm.transfer();
    frame.eax = 0;
    frame.ebx = 0;
    scheduler.unlock();
    interrupts.ret_from_interrupt(&frame);
}

pub fn do_raw(frame: *interrupts.InterruptFrame) void {
    const new_task = task_set.create_task() catch |e| {
        frame.ebx = @intFromError(switch (e) {
            error.TooMuchProcesses => Errno.EAGAIN,
            error.OutOfMemory => Errno.ENOMEM,
        });
        return;
    };
    new_task.clone_vm(scheduler.get_current_task()) catch @panic("todo errno");
    scheduler.lock();
    new_task.spawn(&exec_child, frame.*) catch @panic("todo errno");
    scheduler.unlock();
    frame.eax = @bitCast(new_task.pid);
    frame.ebx = 0;
}
