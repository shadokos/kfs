const std = @import("std");
const task = @import("../task/task.zig");
const scheduler = @import("../task/scheduler.zig");
const task_set = @import("../task/task_set.zig");
const Errno = @import("../errno.zig").Errno;
const interrupts = @import("../interrupts.zig");
const tty = @import("../tty/tty.zig");

const paging = @import("../memory/paging.zig");
const mapping = @import("../memory/mapping.zig");

pub const Id = 7;

fn exec_child(_: usize) u8 {
    const current_task = scheduler.get_current_task();
    if (current_task.vm) |vm|
        vm.transfer();
    const frame = current_task.ucontext.uc_mcontext;
    scheduler.exit_critical();
    for (current_task.files.files[0..], 0..) |f,i| {
        if (f) |g|
        std.log.debug("fork: opened fd: {} {}", .{i, g.inode.ino});
    }
    interrupts.ret_from_interrupt(&frame);
}

pub fn do_raw() void {
    const current_task = scheduler.get_current_task();

    const new_task = task_set.create_task() catch |e| {
        current_task.ucontext.uc_mcontext.ebx = @intFromError(switch (e) {
            error.TooMuchProcesses => Errno.EAGAIN,
            error.OutOfMemory, error.ENOMEM => Errno.ENOMEM,
        });
        return;
    };

    new_task.files = current_task.files.clone();
    new_task.clone_vm(current_task) catch @panic("todo errno");
    new_task.ucontext = current_task.ucontext;
    new_task.tls_base = current_task.tls_base;

    new_task.ucontext.uc_mcontext.eax = 0;
    new_task.ucontext.uc_mcontext.ebx = 0;

    current_task.ucontext.uc_mcontext.eax = @bitCast(new_task.pid);
    current_task.ucontext.uc_mcontext.ebx = 0;

    std.log.debug("parent pid: {}", .{current_task.pid});
    std.log.debug("child pid: {}", .{new_task.pid});
    scheduler.enter_critical();
    new_task.spawn(&exec_child, undefined) catch @panic("todo errno");
    scheduler.exit_critical();
}
