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

var cdevs: [tty.num_ttys]CharDevice = undefined;

/// Minor of the first line that is not a console, as Linux numbers ttyS0.
const LINE_MINOR_BASE: types.minor_t = 64;
var ctty_cdev: CharDevice = undefined;

/// fs/character.zig leaves the device in `data`; what follows needs the
/// terminal it stands for.
fn open(dev: *CharDevice, file: *File) char.CharError!void {
    const minor = dev.devt.minor;
    const index = if (minor >= LINE_MINOR_BASE)
        tty.num_consoles + (minor - LINE_MINOR_BASE)
    else
        minor;

    file.vtable = &file_vtable;
    file.data = &tty.tty_array[index];
    tty.tty_array[index].opened();
}

/// Name a terminal that is not a console, once a driver has claimed it. The
/// minor is all read and write need, so the file layer sees no difference.
pub fn register_line(name: []const u8, index: u8) !void {
    const minor = LINE_MINOR_BASE + (index - tty.num_consoles);
    cdevs[index] = CharDevice.init(name, MAJOR, @intCast(minor), &ops);
    try cdevs[index].register();
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
    // A dropped line reports end of input, POSIX 11.1.10.
    if (terminal_.hung_up) return 0;
    return terminal_.read(buffer);
}

fn write(file: *File, data: []const u8) File.Error.write!usize {
    const terminal_ = terminal(file);
    try job_control.check_write(terminal_, scheduler.get_current_task());
    if (terminal_.hung_up) return error.EIO;
    // Only a process waits on a suspended terminal; kernel output must not
    // block behind a Ctrl-S.
    try terminal_.wait_for_output();
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
        .TCFLSH => {
            try job_control.check_control(terminal_, scheduler.get_current_task());
            switch (@as(control.FlushQueue, @enumFromInt(arg))) {
                .OUTPUT => terminal_.flush_output(),
                .INPUT => terminal_.input_buffer.clear(),
                .BOTH => {
                    terminal_.input_buffer.clear();
                    terminal_.flush_output();
                },
                else => return error.EINVAL,
            }
        },
        .TCXONC => {
            try job_control.check_control(terminal_, scheduler.get_current_task());
            switch (@as(control.FlowAction, @enumFromInt(arg))) {
                .OUTPUT_OFF => terminal_.set_output_stopped(true),
                .OUTPUT_ON => terminal_.set_output_stopped(false),
                // Sending a character to an end a console does not have.
                .INPUT_OFF, .INPUT_ON => {},
                else => return error.EINVAL,
            }
        },
        .TCDRAIN, .TCSBRK => {
            try job_control.check_control(terminal_, scheduler.get_current_task());
            terminal_.drain();
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

    for (cdevs[0..tty.num_consoles], 0..) |*dev, i| {
        var buffer: [CharDevice.CDEV_NAME_LEN]u8 = undefined;
        const name = std.fmt.bufPrint(&buffer, "tty{d}", .{i}) catch continue;
        dev.* = CharDevice.init(name, MAJOR, @intCast(i), &ops);
        dev.register() catch |err|
            log.err("cannot register {s}: {s}", .{ name, @errorName(err) });
    }
}
