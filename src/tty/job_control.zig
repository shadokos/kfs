// Who may read from and write to a terminal, POSIX 11.1.4. Only the caller's
// own controlling terminal is governed; any other is an ordinary file.

const TtyStruct = @import("TtyStruct.zig");
const TaskDescriptor = @import("../task/task.zig").TaskDescriptor;
const task_set = @import("../task/task_set.zig");
const signal = @import("../task/signal.zig");

/// EINTR says a signal was raised and the operation gave up; EIO says the
/// caller is out of reach of the terminal and no signal was raised.
pub const Error = error{ EIO, EINTR };

/// A signal that would be thrown away rather than acted on. POSIX weighs this
/// before stopping anyone.
fn would_be_lost(task: *TaskDescriptor, id: signal.Id) bool {
    if (task.signalManager.get_action(id).sa_handler == signal.SIG_IGN) return true;
    const bit = @as(signal.SigSet, 1) << @intCast(@intFromEnum(id));
    return task.ucontext.uc_sigmask & bit != 0;
}

fn raise(task: *TaskDescriptor, id: signal.Id) void {
    _ = task_set.send_signal_to_group(task.pgid, .{
        .si_signo = .{ .valid = id },
        .si_code = .SI_KERNEL,
        .si_pid = 0,
    });
}

/// Whether this terminal governs the caller at all, and whether the caller is
/// already in the foreground. Null means there is nothing to check.
fn background(terminal: *TtyStruct, task: *TaskDescriptor) bool {
    if (task.session.ctty != terminal) return false;
    const foreground = terminal.foreground_pgid orelse return false;
    return task.pgid != foreground;
}

/// Reading from the background stops the group, POSIX 11.1.4. A group that
/// would not act on SIGTTIN, or that nothing could restart, gets EIO instead.
pub fn check_read(terminal: *TtyStruct, task: *TaskDescriptor) Error!void {
    if (!background(terminal, task)) return;

    if (would_be_lost(task, .SIGTTIN)) return error.EIO;
    if (task_set.is_orphaned_group(task.pgid)) return error.EIO;

    raise(task, .SIGTTIN);
    return error.EINTR;
}

/// Writing from the background only stops the group under TOSTOP. Where a read
/// refuses, a write goes through: the asymmetry is in the spec.
pub fn check_write(terminal: *TtyStruct, task: *TaskDescriptor) Error!void {
    if (!background(terminal, task)) return;
    if (!terminal.config.c_lflag.TOSTOP) return;
    if (would_be_lost(task, .SIGTTOU)) return;
    if (task_set.is_orphaned_group(task.pgid)) return error.EIO;

    raise(task, .SIGTTOU);
    return error.EINTR;
}

/// Setting terminal parameters is treated as a write with TOSTOP always set,
/// POSIX 11.1.4: tcsetattr, tcflush, tcflow, tcdrain, tcsendbreak, tcsetpgrp
/// and tcsetwinsize.
pub fn check_control(terminal: *TtyStruct, task: *TaskDescriptor) Error!void {
    if (!background(terminal, task)) return;
    if (would_be_lost(task, .SIGTTOU)) return;
    if (task_set.is_orphaned_group(task.pgid)) return error.EIO;

    raise(task, .SIGTTOU);
    return error.EINTR;
}
