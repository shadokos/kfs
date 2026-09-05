// The terminals the kernel owns, and how the rest of the kernel writes to one.
// What a terminal is lives in TtyStruct.zig, what is behind one in
// TtyDriver.zig.

const std = @import("std");

pub const TtyStruct = @import("TtyStruct.zig");
pub const TtyDriver = @import("TtyDriver.zig");
pub const termios = @import("termios.zig");

const vt_console = @import("../drivers/tty/vt_console.zig");
const wait_queue = @import("../task/wait_queue.zig");
const scheduler = @import("../task/scheduler.zig");

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

fn has_events(_: *void, _: ?*void) bool {
    for (&tty_array) |*t| if (t.events) return true;
    return false;
}

var input_queue: wait_queue.WaitQueue(.{ .predicate = has_events }) = .{};

/// Flag a terminal as having hardware input waiting, and wake the input task.
/// All an interrupt handler should do.
pub fn notify(t: *TtyStruct) void {
    t.events = true;
    input_queue.try_unblock();
}

/// Turn hardware events into terminal input, forever. POSIX 11.1.5 has the
/// system filling the input queue whether or not anyone is reading, and doing
/// it here keeps the line discipline off the interrupt stack.
pub fn input_task(_: usize) u8 {
    while (true) {
        input_queue.block_no_int(scheduler.get_current_task(), null);
        for (&tty_array) |*t| {
            if (!t.events) continue;
            t.events = false;
            if (t.driver.receive) |receive| receive(t);
        }
    }
}

/// Give a newly opened terminal to the session that opened it, POSIX 11.1.3.
///
/// A session leader with no controlling terminal, opening a terminal no session
/// answers for, gets it. Called from open() rather than from the driver, the
/// flags being what decides and only open() having them.
pub fn acquire_controlling(file: *@import("../fs/file.zig"), no_ctty: bool) void {
    if (no_ctty) return;

    const terminal = @import("../drivers/tty/tty_cdev.zig").terminal_of(file) orelse return;
    const task = scheduler.get_current_task();
    if (task.session.sid != task.pid) return;

    task.session.claim(terminal, task.pgid) catch {};
}

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
