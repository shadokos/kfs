// The terminals the kernel owns, and how the rest of the kernel writes to one.
// What a terminal is lives in TtyStruct.zig, what is behind one in
// TtyDriver.zig.

const std = @import("std");

pub const TtyStruct = @import("TtyStruct.zig");
pub const TtyDriver = @import("TtyDriver.zig");
pub const termios = @import("termios.zig");

const vt_console = @import("../drivers/tty/vt_console.zig");

/// Highest terminal index.
pub const max_tty = 9;

pub var tty_array: [max_tty + 1]TtyStruct = blk: {
    var array: [max_tty + 1]TtyStruct = undefined;
    for (&array, 0..) |*t, i| t.* = .{ .index = i };
    break :blk array;
};

/// Which terminal the screen is showing.
pub var current_tty: u8 = 0;

/// The consoles behind the terminals. One screen between them, so only the
/// displayed one paints, see vt_console.activate.
var consoles: [max_tty + 1]vt_console = undefined;

pub fn get_tty() *TtyStruct {
    return &tty_array[current_tty];
}

/// Show another terminal.
pub fn set_tty(n: u8) !void {
    if (n > max_tty)
        return error.InvalidTty;
    tty_array[current_tty].set_active(false);
    current_tty = n;
    tty_array[current_tty].set_active(true);
}

pub inline fn get_reader() std.io.AnyReader {
    return tty_array[current_tty].reader().any();
}

pub inline fn get_writer() std.io.AnyWriter {
    return tty_array[current_tty].writer().any();
}

pub inline fn get_buffered_writer() *std.io.Writer {
    return ttyBufferWriter[current_tty];
}

/// One buffer per terminal, so a formatted print reaches the terminal in one
/// piece rather than a byte at a time.
var buffers: [max_tty + 1][vt_console.width * vt_console.height]u8 = undefined;

var ttyBufferWriter = init: {
    var array: [max_tty + 1]*std.Io.Writer = undefined;
    for (0..max_tty + 1) |i| {
        array[i] = @constCast(&tty_array[i].writer().adaptToNewApi(&buffers[i]).new_interface);
    }
    break :init array;
};

var write_lock = @import("../task/semaphore.zig").Mutex{};

/// Print to the terminal being shown.
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

/// Give every terminal a console, and show the first one.
pub fn init() void {
    for (&tty_array, &consoles) |*t, *console| {
        console.* = .{};
        console.init(t);
    }
    tty_array[current_tty].set_active(true);
}
