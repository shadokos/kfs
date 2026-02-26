// TTY subsystem module root.
//
// Provides global TTY management: the TTY array, active TTY switching,
// printk/flush, and initialization.
// Hardware drivers (VGA console, serial) register as TtyDriver backends.
const std = @import("std");

pub const TtyStruct = @import("tty_struct.zig");
pub const TtyDriver = @import("tty_driver.zig");
pub const termios = @import("termios.zig");

/// Number of VGA virtual consoles (switchable via keyboard shortcuts).
pub const num_consoles = 5;

/// Maximum number of serial TTY slots.
pub const max_serial = 4;

/// Total number of TTY slots = consoles + serial ports.
pub const total_ttys = num_consoles + max_serial;

pub const max_tty = total_ttys - 1;

// [0..num_consoles-1] = VGA consoles, [num_consoles..] = serial.
// Default-initialized with a no-op driver.
pub var tty_array: [total_ttys]TtyStruct = [1]TtyStruct{TtyStruct{}} ** total_ttys;

pub var current_tty: u8 = 0;

pub fn get_tty() *TtyStruct {
    return &tty_array[current_tty];
}

/// Switch active console (only console slots are valid).
pub fn set_tty(n: u8) !void {
    if (n >= num_consoles)
        return error.InvalidTty;
    current_tty = n;

    tty_array[current_tty].driver_flush();
}

pub inline fn get_reader() std.io.AnyReader {
    return tty_array[current_tty].reader().any();
}

pub inline fn get_writer() std.io.AnyWriter {
    return tty_array[current_tty].writer().any();
}

pub const width = 80;
pub const height = 25;

var buffers: [total_ttys][width * height]u8 = undefined;

var ttyBufferWriter = init: {
    var array: [total_ttys]*std.io.Writer = undefined;
    for (0..total_ttys) |i| {
        array[i] = @constCast(
            &tty_array[i].writer().adaptToNewApi(&buffers[i]).new_interface,
        );
    }
    break :init array;
};

pub inline fn get_buffered_writer() *std.io.Writer {
    return ttyBufferWriter[current_tty];
}

var write_lock = @import("../../task/semaphore.zig").Mutex{};

pub inline fn printk(comptime fmt: []const u8, args: anytype) void {
    write_lock.acquire();
    defer write_lock.release();
    ttyBufferWriter[current_tty].print(fmt, args) catch {};
}

pub inline fn flush() void {
    write_lock.acquire();
    defer write_lock.release();
    ttyBufferWriter[current_tty].flush() catch {};
}

/// Initialize console TTYs with the given driver.
/// Serial slots keep the default no-op driver until serial_tty.init().
pub fn init(driver: *const TtyDriver) void {
    for (tty_array[0..num_consoles], 0..) |*t, i| {
        t.index = @intCast(i);
        t.driver = driver;
    }
}
