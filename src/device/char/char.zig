const std = @import("std");

const CharDevice = @import("cdev.zig");

pub const CharError = error{
    DeviceNotFound,
    DeviceBusy,
    InvalidOperation,
    IoError,
    NoData,
    WouldBlock,
    NotSupported,
    PermissionDenied,
    OutOfMemory,
};

/// VTable for character device drivers.
///
/// `write` is the only field typically required. Devices that are read-only
/// (e.g. /dev/random) or write-only (e.g. /dev/null) may leave the other as null.
///
/// Every function receives the `CharDevice` itself. Drivers that need their own
/// state should embed the CharDevice in their struct and use `@fieldParentPtr`.
pub const Operations = struct {
    open: ?*const fn (dev: *CharDevice) CharError!void = null,
    release: ?*const fn (dev: *CharDevice) void = null,
    read: ?*const fn (dev: *CharDevice, buffer: []u8) CharError!usize = null,
    write: ?*const fn (dev: *CharDevice, data: []const u8) CharError!usize = null,
    ioctl: ?*const fn (dev: *CharDevice, cmd: u32, arg: usize) CharError!usize = null,
    destroy: ?*const fn (dev: *CharDevice) void = null,
};
