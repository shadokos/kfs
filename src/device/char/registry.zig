const std = @import("std");

const core = @import("char.zig");
const CharDevice = @import("cdev.zig");
const dev_t = core.dev_t;
const udev_t = core.udev_t;
const major_t = core.major_t;
const minor_t = core.minor_t;

const Errno = @import("../../errno.zig").Errno;

const allocator = @import("../../memory.zig").smallAlloc.allocator();
const MAX_MAJOR = std.math.maxInt(major_t);

/// Registered character device majors (index = major number).
var majors: [MAX_MAJOR]?[]const u8 = .{null} ** MAX_MAJOR;

/// Treap for registered char devices, keyed by dev_t.
const Treap = std.Treap(*CharDevice, compare);
const TreapNode = Treap.Node;

fn compare(a: *CharDevice, b: *CharDevice) std.math.Order {
    return std.math.order(a.devt.toInt(), b.devt.toInt());
}

var devices = Treap{};

// Major number registration

/// Reserve a major number for a character device driver.
pub fn register_char_dev(major: major_t, name: []const u8) !void {
    if (majors[major]) |_| return Errno.EBUSY;
    majors[major] = name;
}

/// Release a major number.
pub fn unregister_char_dev(major: major_t) void {
    majors[major] = null;
}

// Device registration

/// Add a character device to the global device treap.
pub fn register_device(dev: *CharDevice) !void {
    var entry = devices.getEntryFor(dev);
    if (entry.node) |_| return Errno.EEXIST;
    const node: *TreapNode = allocator.create(TreapNode) catch return Errno.ENOSPC;
    node.key = dev;
    entry.set(node);
}

/// Remove a character device from the treap.
pub fn unregister_device(devt: dev_t) void {
    // We need a dummy device whose devt matches the key we're searching for.
    var dummy: CharDevice = undefined;
    dummy.devt = devt;
    var entry = devices.getEntryFor(&dummy);
    if (entry.node) |n| {
        entry.set(null);
        allocator.destroy(n);
    }
}

// Lookup helpers

/// Lookup a character device by dev_t.
pub fn get_device(devt: dev_t) ?*CharDevice {
    var dummy: CharDevice = undefined;
    dummy.devt = devt;
    const entry = devices.getEntryFor(&dummy);
    if (entry.node) |n| return n.key;
    return null;
}

/// Lookup a character device by name.
pub fn get_device_by_name(name: []const u8) ?*CharDevice {
    var it = devices.inorderIterator();
    while (it.next()) |entry| {
        const dev = entry.key;
        if (std.mem.eql(u8, std.mem.sliceTo(&dev.name, 0), name)) {
            return dev;
        }
    }
    return null;
}

// Display (shell / proc)

/// Print registered character device majors (like /proc/devices).
pub fn show_char_dev(writer: std.io.AnyWriter) void {
    _ = writer.print("Character devices:\n", .{}) catch {};
    for (majors, 0..) |name, major| {
        if (name) |n| {
            _ = writer.print("{d: >4} {s}\n", .{ major, n }) catch {};
        }
    }
}

/// List character devices, optionally filtered by name.
pub fn show_lschar(writer: std.io.AnyWriter, filter: ?[]const u8) void {
    _ = writer.print(
        "\n{s: <12} {s: >5}:{s: <5} {s: >4} {s: <6} {s}\n",
        .{ "Device", "major", "minor", "refs", "ops", "driver" },
    ) catch {};

    var found = false;
    var it = devices.inorderIterator();
    while (it.next()) |entry| {
        const dev = entry.key;
        const dev_name = std.mem.sliceTo(&dev.name, 0);

        if (filter) |f| {
            if (!std.mem.eql(u8, dev_name, f)) continue;
        }

        found = true;
        const driver_name = majors[dev.devt.major] orelse "???";

        var ops_buf: [3]u8 = .{ '-', '-', '-' };
        if (dev.ops.read != null) ops_buf[0] = 'R';
        if (dev.ops.write != null) ops_buf[1] = 'W';
        if (dev.ops.ioctl != null) ops_buf[2] = 'I';

        _ = writer.print(
            "{s: <12} {d: >5}:{d: <5} {d: >4} {s: <6} {s}\n",
            .{
                dev_name,
                dev.devt.major,
                dev.devt.minor,
                dev.ref_count,
                &ops_buf,
                driver_name,
            },
        ) catch {};
    }

    if (!found) {
        if (filter) |f| {
            _ = writer.print("No character device matching '{s}'\n", .{f}) catch {};
        } else {
            _ = writer.print("(no character devices registered)\n", .{}) catch {};
        }
    }
}

// Init

pub fn init() void {
    // No default majors registered yet. Drivers will register
    // their own majors when they are initialized (e.g. TTY, serial).
}
