const ft = @import("../ft/ft.zig");
const task = @import("task.zig");
const TaskDescriptor = task.TaskDescriptor;
const scheduler = @import("scheduler.zig");
const task_set = @import("task_set.zig");
const signal = @import("signal.zig");
const Errno = @import("errno.zig").Errno;
const status_informations = @import("status_informations.zig");

pub const WaitOptions = packed struct(u32) {
    WCONTINUED: bool = false,
    WNOHANG: bool = false,
    WUNTRACED: bool = false,
    _unused: u29 = undefined,
};

pub const Selector = enum {
    SELF,
    CHILD,
};

pub const Status = packed struct(u32) {
    type: Type,
    value: u8,
    _unused: u16 = 0,
    pub const Type = enum(u8) {
        Exited = 1,
        Stopped = 2,
        Continued = 3,
        Signaled = 4,
    };

    pub fn from_status_info(si: status_informations.Status) Status {
        return switch (si.transition) {
            status_informations.Status.Transition.Stopped => .{
                .type = Type.Stopped,
                .value = @truncate(si.siginfo.si_signo),
            },
            status_informations.Status.Transition.Continued => .{
                .type = Type.Continued,
                .value = undefined,
            },
            status_informations.Status.Transition.Terminated => if (si.signaled) .{
                .type = Type.Signaled,
                .value = @truncate(si.siginfo.si_signo),
            } else .{
                .type = Type.Exited,
                .value = @truncate(si.siginfo.si_status),
            },
        };
    }
};

fn wait_selector(
    descriptor: *TaskDescriptor,
    selector: Selector,
    transition: status_informations.Status.Transition,
) Errno!?*TaskDescriptor {
    return switch (selector) {
        .SELF => descriptor.autowait(transition),
        .CHILD => descriptor.wait_child(transition),
    };
}

fn wait_transition(descriptor: *TaskDescriptor, selector: Selector, options: WaitOptions) Errno!?*TaskDescriptor {
    return try wait_selector(
        descriptor,
        selector,
        .Terminated,
    ) orelse (if (options.WCONTINUED) try wait_selector(
        descriptor,
        selector,
        .Continued,
    ) else null) orelse (if (options.WUNTRACED) try wait_selector(
        descriptor,
        selector,
        .Stopped,
    ) else null);
}

pub fn wait(
    pid: TaskDescriptor.Pid,
    selector: Selector,
    stat_loc: *Status,
    options: WaitOptions,
) Errno!?TaskDescriptor.Pid {
    const descriptor = task_set.get_task_descriptor(pid) orelse return Errno.ECHILD; // todo
    if (options._unused != 0) {
        return Errno.EINVAL;
    }
    // todo ESRCH
    // const current_task = scheduler.get_current_task();
    // if (descriptor.parent != current_task) {
    //     return error.InvalidPid; // todo
    // }
    while (true) {
        if (try wait_transition(descriptor, selector, options)) |d| {
            const status_info = d.get_status() orelse unreachable;
            stat_loc.* = Status.from_status_info(status_info);
            if (status_info.transition == .Terminated) {
                task_set.destroy_task(d.pid) catch @panic("je panique la");
            }
            return d.pid;
        }
        if (options.WNOHANG) {
            return null;
        }
        scheduler.schedule();
        // todo signals
    }
}
