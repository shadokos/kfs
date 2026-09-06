// The terminals as character special files, POSIX 11.1.1. Major 4, one minor
// per console, named ttyN by devfs from the registry.

const std = @import("std");

const File = @import("../../fs/file.zig");
const char = @import("../../device/char/char.zig");
const CharDevice = @import("../../device/char/cdev.zig");
const registry = @import("../../device/char/registry.zig");
const types = @import("../../device/types.zig");

const tty = @import("../../tty/tty.zig");
const TtyStruct = @import("../../tty/TtyStruct.zig");
const termios = @import("../../tty/termios.zig");
const control = @import("../../tty/ioctl.zig");
const job_control = @import("../../tty/job_control.zig");
const task_set = @import("../../task/task_set.zig");
const scheduler = @import("../../task/scheduler.zig");
const TaskDescriptor = @import("../../task/task.zig").TaskDescriptor;

const log = std.log.scoped(.tty_cdev);

const MAJOR: types.major_t = 4;

/// /dev/tty, resolved at every open to the caller's controlling terminal.
const CTTY_MAJOR: types.major_t = 5;

var cdevs: [tty.max_tty + 1]CharDevice = undefined;
var ctty_cdev: CharDevice = undefined;

/// fs/character.zig leaves the device in `data`; what follows needs the
/// terminal it stands for.
fn open(dev: *CharDevice, file: *File) char.CharError!void {
    file.vtable = &file_vtable;
    file.data = &tty.tty_array[dev.devt.minor];
}

/// Open the controlling terminal of the calling session, POSIX 11.1.1. A
/// session without one gets ENXIO.
fn open_ctty(_: *CharDevice, file: *File) char.CharError!void {
    const session = @import("../../task/scheduler.zig").get_current_task().session;
    file.data = session.ctty orelse return error.DeviceNotFound;
    file.vtable = &file_vtable;
}

const ctty_ops = char.Operations{ .open = &open_ctty };

fn terminal(file: *File) *TtyStruct {
    return @ptrCast(@alignCast(file.data.?));
}

/// The terminal an open file stands for, or null. The vtable tells them apart:
/// only a file opened here carries a TtyStruct in `data`.
pub fn terminal_of(file: *File) ?*TtyStruct {
    if (file.vtable != &file_vtable) return null;
    return terminal(file);
}

// Access control belongs on the descriptor path, POSIX 11.1.4: kernel output
// has no process group.

fn read(file: *File, buffer: []u8) File.Error.read!usize {
    const terminal_ = terminal(file);
    try job_control.check_read(terminal_, scheduler.get_current_task());
    return terminal_.read(buffer);
}

fn write(file: *File, data: []const u8) File.Error.write!usize {
    const terminal_ = terminal(file);
    try job_control.check_write(terminal_, scheduler.get_current_task());
    return terminal_.write(data);
}

/// The control requests POSIX reaches through tcgetattr and tcsetattr. With no
/// output queue, DRAIN and FLUSH apply at once like NOW.
fn ioctl(file: *File, request: u32, arg: usize) File.Error.ioctl!usize {
    const terminal_ = terminal(file);

    switch (@as(control.Request, @enumFromInt(request))) {
        .TCGETS => {
            const out: *termios.abi.Termios = @ptrFromInt(arg);
            out.* = termios.to_abi(terminal_.config);
        },
        .TCSETS, .TCSETSW, .TCSETSF => |request_| {
            try job_control.check_control(terminal_, scheduler.get_current_task());
            const new: *const termios.abi.Termios = @ptrFromInt(arg);
            if (request_ == .TCSETSF) terminal_.input_buffer.clear();
            terminal_.set_termios(termios.from_abi(new.*));
        },
        .TIOCGPGRP => {
            // POSIX tcgetpgrp: only the caller's own terminal answers.
            const task = scheduler.get_current_task();
            if (task.session.ctty != terminal_) return error.ENOTTY;

            const out: *TaskDescriptor.Pid = @ptrFromInt(arg);
            // No foreground group is reported as a group id that matches none.
            out.* = terminal_.foreground_pgid orelse std.math.maxInt(TaskDescriptor.Pid);
        },
        .TIOCSPGRP => {
            const task = scheduler.get_current_task();
            if (task.session.ctty != terminal_) return error.ENOTTY;
            try job_control.check_control(terminal_, task);

            const wanted: *const TaskDescriptor.Pid = @ptrFromInt(arg);
            if (wanted.* <= 0) return error.EINVAL;
            // A group of another session would leave the terminal unreachable.
            const member = task_set.find_in_group(wanted.*) orelse return error.EPERM;
            if (member.session != task.session) return error.EPERM;

            _ = terminal_.set_foreground_pgid(wanted.*);
        },
        .TIOCGSID => {
            // POSIX tcgetsid: a terminal no session answers for is not the
            // caller's either.
            const owner = terminal_.session orelse return error.ENOTTY;
            const out: *TaskDescriptor.Pid = @ptrFromInt(arg);
            out.* = owner.sid;
        },
        .TIOCSCTTY => {
            const task = scheduler.get_current_task();
            if (task.session.sid != task.pid) return error.EPERM;
            // Stealing a terminal from another session is not offered.
            task.session.claim(terminal_, task.pgid) catch return error.EPERM;
        },
        .TIOCNOTTY => {
            const session = scheduler.get_current_task().session;
            if (session.ctty != terminal_) return error.ENOTTY;
            session.hangup();
        },
        else => return error.EINVAL,
    }
    return 0;
}

pub const ops = char.Operations{ .open = &open };

pub const file_vtable = File.VTable{
    .read = &read,
    .write = &write,
    .close = &File.VTable.Generic.close,
    .ioctl = &ioctl,
};

pub fn init() void {
    registry.register_char_dev(MAJOR, "tty") catch |err| {
        log.err("cannot reserve major {d}: {s}", .{ MAJOR, @errorName(err) });
        return;
    };

    registry.register_char_dev(CTTY_MAJOR, "tty") catch |err| {
        log.err("cannot reserve major {d}: {s}", .{ CTTY_MAJOR, @errorName(err) });
        return;
    };
    ctty_cdev = CharDevice.init("tty", CTTY_MAJOR, 0, &ctty_ops);
    ctty_cdev.register() catch |err|
        log.err("cannot register tty: {s}", .{@errorName(err)});

    for (&cdevs, 0..) |*dev, i| {
        var buffer: [CharDevice.CDEV_NAME_LEN]u8 = undefined;
        const name = std.fmt.bufPrint(&buffer, "tty{d}", .{i}) catch continue;
        dev.* = CharDevice.init(name, MAJOR, @intCast(i), &ops);
        dev.register() catch |err|
            log.err("cannot register {s}: {s}", .{ name, @errorName(err) });
    }
}
