const char = @import("../../../device/char/char.zig");
const CharDevice = @import("../../../device/char/cdev.zig");
const CharError = char.CharError;

pub const MINOR: char.minor_t = 5;

/// Singleton instance, initialized by mem.init() and lives for the entire kernel lifetime.
pub var cdev: CharDevice = undefined;

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
