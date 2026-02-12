const std = @import("std");

const char = @import("../../../device/char/char.zig");
const cdev = @import("../../../device/char/cdev.zig");

const CharDevice = cdev;
const CharError = char.CharError;

pub const MINOR: char.minor_t = 5;

fn zero_read(_: *CharDevice, buffer: []u8) CharError!usize {
    // Reading from /dev/zero fills buffer with zeroes
    @memset(buffer, 0);
    return buffer.len;
}

fn zero_write(_: *CharDevice, data: []const u8) CharError!usize {
    // Writing to /dev/zero always succeeds, data is discarded
    return data.len;
}

pub const ops = char.Operations{
    .read = zero_read,
    .write = zero_write,
};
