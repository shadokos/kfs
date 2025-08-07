const task = @import("task.zig");
const TaskDescriptor = task.TaskDescriptor;
const scheduler = @import("scheduler.zig");
const task_set = @import("task_set.zig");
const signal = @import("signal.zig");
const Errno = @import("../errno.zig").Errno;
const status_informations = @import("status_informations.zig");
const wait_queues = @import("wait_queue.zig");

pub const WaitOptions = packed struct(u32) {
    WCONTINUED: bool = false,
    WNOHANG: bool = false,
    WUNTRACED: bool = false,
    _unused: u29 = 0,
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
                .value = @intCast(@as(u32, @intFromEnum(si.siginfo.si_signo.unwrap()))),
            },
            status_informations.Status.Transition.Continued => .{
                .type = Type.Continued,
                .value = undefined,
            },
            status_informations.Status.Transition.Terminated => if (si.signaled) .{
                .type = Type.Signaled,
                .value = @intCast(@as(u32, @intFromEnum(si.siginfo.si_signo.unwrap()))),
            } else .{
                .type = Type.Exited,
                .value = @truncate(si.siginfo.si_status),
            },
        };
    }
};

const WaitRequest = struct {
    selector: Selector,
    transition_mask: status_informations.Status.TransitionMask,
    pid: TaskDescriptor.Pid,
};

fn predicate(_: *void, wait_request_ptr: ?*void) bool {
    const wait_request = @as(*WaitRequest, @alignCast(@ptrCast(wait_request_ptr.?))).*;
    const waited_task = task_set.get_task_descriptor(wait_request.pid) orelse return true;

    return switch (wait_request.selector) {
        .SELF => waited_task.autowait(wait_request.transition_mask) != null,
        .CHILD => waited_task.wait_child(wait_request.transition_mask) != null,
    };
}

pub const WaitQueue = wait_queues.WaitQueue(.{
    .predicate = predicate,
});

pub fn get_task_nohang(
    descriptor: *TaskDescriptor,
    request: WaitRequest,
    selector: Selector,
) ?*TaskDescriptor {
    return switch (selector) {
        .SELF => descriptor.autowait(request.transition_mask),
        .CHILD => descriptor.wait_child(request.transition_mask),
    };
}

pub fn get_task(
    descriptor: *TaskDescriptor,
    request: WaitRequest,
    selector: Selector,
) !?*TaskDescriptor {
    var var_request = request;
    try scheduler.get_current_task().status_wait_queue.block(scheduler.get_current_task(), @ptrCast(&var_request));
    return get_task_nohang(descriptor, request, selector);
}

pub fn wait(
    pid: TaskDescriptor.Pid,
    selector: Selector,
    stat_loc: ?*Status,
    siginfo: ?*signal.siginfo_t,
    options: WaitOptions,
) Errno!TaskDescriptor.Pid {
    const descriptor = task_set.get_task_descriptor(pid) orelse return Errno.ECHILD;
    if (options._unused != 0) {
        return Errno.EINVAL;
    }
    if ((selector == .CHILD and descriptor.childs == null) or
        (selector == .SELF and descriptor.parent != scheduler.get_current_task()))
    {
        return Errno.ECHILD;
    }

    const request = WaitRequest{ .selector = selector, .pid = pid, .transition_mask = .{
        .Continued = options.WCONTINUED,
        .Stopped = options.WUNTRACED,
        .Terminated = true,
    } };

    const waited_task: *TaskDescriptor = switch (options.WNOHANG) {
        true => get_task_nohang(descriptor, request, selector) orelse {
            if (siginfo) |s| {
                s.* = .{
                    .si_pid = 0,
                    .si_signo = signal.siginfo_t.Signo.invalid,
                };
            }
            return 0;
        },
        false => try get_task(descriptor, request, selector) orelse return Errno.EINTR,
    };

    // if (options.WNOWAIT)
    //     return waited_task.pid;

    const status_info = waited_task.get_status() orelse @panic("todo: task waited but no status");

    if (stat_loc) |sl|
        sl.* = Status.from_status_info(status_info);

    if (siginfo) |s| {
        s.* = status_info.siginfo;
        s.*.si_signo = .{ .valid = .SIGCHLD };
    }

    defer if (status_info.transition == .Terminated) {
        task_set.destroy_task(waited_task.pid) catch @panic("todo: failed to destroy task");
    };

    return waited_task.pid;
}
