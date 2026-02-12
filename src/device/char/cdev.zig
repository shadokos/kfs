const std = @import("std");

const core = @import("char.zig");
const CharError = core.CharError;
const Operations = core.Operations;
const dev_t = core.dev_t;
const major_t = core.major_t;
const minor_t = core.minor_t;

const registry = @import("registry.zig");

const allocator = @import("../../memory.zig").smallAlloc.allocator();

pub const CDEV_NAME_LEN = 16;

const Self = @This();

name: [CDEV_NAME_LEN:0]u8,
devt: dev_t,
ops: *const Operations,
private_data: ?*anyopaque = null,
ref_count: u32 = 0,

/// Allocate and initialize a new CharDevice.
pub fn create(
    name: []const u8,
    major: major_t,
    minor: minor_t,
    ops: *const Operations,
) !*Self {
    const dev: *Self = try allocator.create(Self);
    errdefer allocator.destroy(dev);

    dev.* = .{
        .name = .{0} ** CDEV_NAME_LEN,
        .devt = .{ .major = major, .minor = minor },
        .ops = ops,
    };

    // Copy name (truncated to CDEV_NAME_LEN - 1)
    const copy_len = @min(name.len, CDEV_NAME_LEN - 1);
    @memcpy(dev.name[0..copy_len], name[0..copy_len]);

    try registry.register_device(dev);
    errdefer registry.unregister_device(dev.devt);

    return dev;
}

/// Release resources and remove from registry.
pub fn destroy(self: *Self) void {
    registry.unregister_device(self.devt);
    if (self.ops.destroy) |destroy_fn| {
        destroy_fn(self);
    }
    allocator.destroy(self);
}

/// Open the device (increments ref count).
pub fn open(self: *Self) CharError!void {
    if (self.ops.open) |open_fn| {
        try open_fn(self);
    }
    self.ref_count += 1;
}

/// Release the device (decrements ref count).
pub fn release(self: *Self) void {
    if (self.ref_count > 0) self.ref_count -= 1;
    if (self.ops.release) |release_fn| {
        release_fn(self);
    }
}

/// Read bytes from the device into buffer.
/// Returns the number of bytes read, or CharError if the device doesn't support reading.
pub fn read(self: *Self, buffer: []u8) CharError!usize {
    const read_fn = self.ops.read orelse return CharError.NotSupported;
    return read_fn(self, buffer);
}

/// Write bytes to the device.
/// Returns the number of bytes written, or CharError if the device doesn't support writing.
pub fn write(self: *Self, data: []const u8) CharError!usize {
    const write_fn = self.ops.write orelse return CharError.NotSupported;
    return write_fn(self, data);
}

/// Perform an ioctl operation.
pub fn ioctl(self: *Self, cmd: u32, arg: usize) CharError!usize {
    const ioctl_fn = self.ops.ioctl orelse return CharError.NotSupported;
    return ioctl_fn(self, cmd, arg);
}
