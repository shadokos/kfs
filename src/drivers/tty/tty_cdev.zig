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

const log = std.log.scoped(.tty_cdev);

const MAJOR: types.major_t = 4;

var cdevs: [tty.max_tty + 1]CharDevice = undefined;

/// fs/character.zig leaves the device in `data`; what follows needs the
/// terminal it stands for.
fn open(dev: *CharDevice, file: *File) char.CharError!void {
    file.vtable = &file_vtable;
    file.data = &tty.tty_array[dev.devt.minor];
}

fn terminal(file: *File) *TtyStruct {
    return @ptrCast(@alignCast(file.data.?));
}

/// The terminal an open file stands for, or null. The vtable tells them apart:
/// only a file opened here carries a TtyStruct in `data`.
pub fn terminal_of(file: *File) ?*TtyStruct {
    if (file.vtable != &file_vtable) return null;
    return terminal(file);
}

fn read(file: *File, buffer: []u8) File.Error.read!usize {
    return terminal(file).read(buffer);
}

fn write(file: *File, data: []const u8) File.Error.write!usize {
    return terminal(file).write(data);
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
            const new: *const termios.abi.Termios = @ptrFromInt(arg);
            if (request_ == .TCSETSF) terminal_.input_buffer.clear();
            terminal_.set_termios(termios.from_abi(new.*));
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

    for (&cdevs, 0..) |*dev, i| {
        var buffer: [CharDevice.CDEV_NAME_LEN]u8 = undefined;
        const name = std.fmt.bufPrint(&buffer, "tty{d}", .{i}) catch continue;
        dev.* = CharDevice.init(name, MAJOR, @intCast(i), &ops);
        dev.register() catch |err|
            log.err("cannot register {s}: {s}", .{ name, @errorName(err) });
    }
}
