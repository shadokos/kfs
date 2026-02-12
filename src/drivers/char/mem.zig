/// Memory character devices: /dev/null and /dev/zero
///
/// Follows the Linux convention (Major 1):
///   - Minor 3: /dev/null
///   - Minor 5: /dev/zero
const std = @import("std");

const char = @import("../../device/char/char.zig");
const cdev = @import("../../device/char/cdev.zig");
const registry = @import("../../device/char/registry.zig");

// Submodules
pub const null_dev = @import("mem/null.zig");
pub const zero_dev = @import("mem/zero.zig");

const log = std.log.scoped(.chardev_mem);

const MAJOR: char.major_t = 1;

pub fn init() void {
    registry.register_char_dev(MAJOR, "mem") catch |err| {
        log.err("Failed to register mem major: {s}", .{@errorName(err)});
        return;
    };

    _ = cdev.create("null", MAJOR, null_dev.MINOR, &null_dev.ops) catch |err| {
        log.err("Failed to create /dev/null: {s}", .{@errorName(err)});
        return;
    };

    _ = cdev.create("zero", MAJOR, zero_dev.MINOR, &zero_dev.ops) catch |err| {
        log.err("Failed to create /dev/zero: {s}", .{@errorName(err)});
        return;
    };

    log.info("mem devices initialized (null, zero)", .{});
}
