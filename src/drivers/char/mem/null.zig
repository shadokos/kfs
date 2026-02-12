const char = @import("../../../device/char/char.zig");
const CharDevice = @import("../../../device/char/cdev.zig");
const CharError = char.CharError;

pub const MINOR: char.minor_t = 3;

/// Singleton instance, initialized by mem.init() and lives for the entire kernel lifetime.
pub var cdev: CharDevice = undefined;

fn null_read(_: *CharDevice, _: []u8) CharError!usize {
    // Reading from /dev/null always returns EOF (0 bytes)
    return 0;
}

fn null_write(_: *CharDevice, data: []const u8) CharError!usize {
    // Writing to /dev/null always succeeds, data is discarded
    return data.len;
}

pub const ops = char.Operations{
    .read = null_read,
    .write = null_write,
};
