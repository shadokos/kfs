const std = @import("std");
const Inode = @import("inode.zig");
const File = @import("file.zig");
const memory = @import("../memory.zig");
const registry = @import("../device/char/registry.zig");
const CharDevice = @import("../device/char/cdev.zig");

pub fn open(base: *Inode, file: *File) Inode.Error.open!void {
    const device = registry.get_device(base.type_specific.Character) orelse return error.ENXIO;
    file.* = .{
        .vtable = undefined,
        .inode = base.get_ref(),
        .refs = 1,
        .data = device,
    };
    // /dev/tty without a controlling terminal has to reach the caller as ENXIO.
    device.open(file) catch |err| return switch (err) {
        error.DeviceNotFound => error.ENXIO,
        error.OutOfMemory => error.ENOMEM,
        error.PermissionDenied => error.EPERM,
        else => error.EIO,
    };
}

fn read(file: *File, buffer: []u8) File.Error.read!usize {
    const device: *CharDevice = @ptrCast(@alignCast(file.data.?));
    return device.read(buffer) catch return error.EIO;
}

fn write(file: *File, buffer: []const u8) File.Error.write!usize {
    const device: *CharDevice = @ptrCast(@alignCast(file.data.?));
    return device.write(buffer) catch return error.EIO;
}

fn close(file: *File) File.Error.close!void {
    const device: *CharDevice = @ptrCast(@alignCast(file.data.?));
    device.release();
    file.inode.release();
}

pub const file_vtable: File.VTable = .{
    .read = &read,
    .write = &write,
    .close = &close,
};
