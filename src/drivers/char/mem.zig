/// Memory character devices: /dev/null and /dev/zero
///
/// Follows the Linux convention (Major 1):
///   - Minor 3: /dev/null
///   - Minor 5: /dev/zero
const std = @import("std");

const char = @import("../../device/char/char.zig");
const registry = @import("../../device/char/registry.zig");

pub const null_dev = @import("mem/null.zig");
pub const zero_dev = @import("mem/zero.zig");

const log = std.log.scoped(.chardev_mem);

const MAJOR: char.major_t = 1;

pub fn init() void {
    registry.register_char_dev(MAJOR, "mem") catch |err| {
        log.err("Failed to register mem major: {s}", .{@errorName(err)});
        return;
    };

    const CharDevice = @import("../../device/char/cdev.zig");

    null_dev.cdev = CharDevice.init("null", MAJOR, null_dev.MINOR, &null_dev.ops);
    null_dev.cdev.register() catch |err| {
        log.err("Failed to register /dev/null: {s}", .{@errorName(err)});
        return;
    };

    zero_dev.cdev = CharDevice.init("zero", MAJOR, zero_dev.MINOR, &zero_dev.ops);
    zero_dev.cdev.register() catch |err| {
        log.err("Failed to register /dev/zero: {s}", .{@errorName(err)});
        return;
    };

    log.info("mem devices initialized (null, zero)", .{});
}
