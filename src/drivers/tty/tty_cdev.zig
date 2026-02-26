// TTY character device registration.
//
// Registers TTY consoles and serial ports as character devices:
//   Major 4, Minors 0..N     = /dev/ttyN (virtual consoles)
//   Major 4, Minors 64..67   = /dev/ttyS0..S3 (serial ports)
const std = @import("std");

const char = @import("../../device/char/char.zig");
const CharDevice = @import("../../device/char/cdev.zig");
const registry = @import("../../device/char/registry.zig");
const CharError = char.CharError;

const tty_mod = @import("../../device/tty/tty.zig");
const TtyStruct = @import("../../device/tty/tty_struct.zig");

const log = std.log.scoped(.chardev_tty);

/// Major number for TTY devices (both consoles and serial).
const TTY_MAJOR: char.major_t = 4;

/// Minor offset for serial ports: ttyS0 = minor 64.
const SERIAL_MINOR_BASE: char.minor_t = 64;

var tty_current_cdev: CharDevice = undefined;

fn tty_current_read(_: *CharDevice, buffer: []u8) CharError!usize {
    return tty_mod.get_tty().read(buffer) catch return CharError.IOError;
}

fn tty_current_write(_: *CharDevice, data: []const u8) CharError!usize {
    return tty_mod.get_tty().write(data) catch return CharError.IOError;
}

const tty_current_ops = char.Operations{
    .read = tty_current_read,
    .write = tty_current_write,
};

// /dev/ttyN (virtual consoles)

var tty_cdevs: [tty_mod.num_consoles]CharDevice = undefined;

fn tty_read(dev: *CharDevice, buffer: []u8) CharError!usize {
    const tty_s = &tty_mod.tty_array[dev.devt.minor];
    return tty_s.read(buffer) catch return CharError.IOError;
}

fn tty_write(dev: *CharDevice, data: []const u8) CharError!usize {
    const tty_s = &tty_mod.tty_array[dev.devt.minor];
    return tty_s.write(data) catch return CharError.IOError;
}

const tty_ops = char.Operations{
    .read = tty_read,
    .write = tty_write,
};

// /dev/ttySN (serial ports)

const MAX_SERIAL_PORTS = 4;
var serial_cdevs: [MAX_SERIAL_PORTS]CharDevice = undefined;
var serial_count: usize = 0;

fn serial_read(dev: *CharDevice, buffer: []u8) CharError!usize {
    const idx = dev.devt.minor - SERIAL_MINOR_BASE;
    const tty_s = &tty_mod.tty_array[tty_mod.num_consoles + idx];
    return tty_s.read(buffer) catch return CharError.IOError;
}

fn serial_write(dev: *CharDevice, data: []const u8) CharError!usize {
    const idx = dev.devt.minor - SERIAL_MINOR_BASE;
    const tty_s = &tty_mod.tty_array[tty_mod.num_consoles + idx];
    return tty_s.write(data) catch return CharError.IOError;
}

const serial_ops = char.Operations{
    .read = serial_read,
    .write = serial_write,
};

/// Register a serial port as /dev/ttySN. Returns the minor assigned.
pub fn register_serial(name: []const u8) !char.minor_t {
    if (serial_count >= MAX_SERIAL_PORTS) return error.TooManySerialPorts;
    const minor: char.minor_t = SERIAL_MINOR_BASE + @as(char.minor_t, @intCast(serial_count));
    serial_cdevs[serial_count] = CharDevice.init(name, TTY_MAJOR, minor, &serial_ops);
    serial_cdevs[serial_count].register() catch |err| {
        log.err("Failed to register /dev/{s}: {s}", .{ name, @errorName(err) });
        return err;
    };
    serial_count += 1;
    return minor;
}

pub fn init() void {
    // Register the major number
    registry.register_char_dev(TTY_MAJOR, "tty") catch |err| {
        log.err("Failed to register tty major: {s}", .{@errorName(err)});
        return;
    };

    // Register /dev/tty0.../dev/ttyN (virtual consoles)
    for (0..tty_mod.num_consoles) |i| {
        var name_buf: [CharDevice.CDEV_NAME_LEN:0]u8 = .{0} ** CharDevice.CDEV_NAME_LEN;
        _ = std.fmt.bufPrint(&name_buf, "tty{d}", .{i}) catch continue;

        tty_cdevs[i] = CharDevice.init(
            std.mem.sliceTo(&name_buf, 0),
            TTY_MAJOR,
            @intCast(i),
            &tty_ops,
        );
        tty_cdevs[i].register() catch |err| {
            log.err("Failed to register /dev/tty{d}: {s}", .{ i, @errorName(err) });
            continue;
        };
    }

    log.info("tty devices initialized (tty, tty0-tty{d})", .{tty_mod.num_consoles - 1});
}
