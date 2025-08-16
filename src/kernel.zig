const std = @import("std");
const DefaultShell = @import("shell/default/shell.zig");
const tty = @import("./tty/tty.zig");
// const ide = @import("./drivers/ide/ide.zig");
const timer = @import("timer.zig");
const logger = std.log.scoped(.main);

fn test_device(name: []const u8) void {
    const storage = @import("storage/storage.zig");

    if (storage.findDevice(name)) |device| {
        logger.info("Found device: {s}", .{device.getName()});
        const allocator = @import("memory.zig").bigAlloc.allocator();
        const buffer = allocator.alloc(u8, 2048) catch |err| {
            logger.err("Failed to allocate buffer: {s}", .{@errorName(err)});
            return;
        };
        defer allocator.free(buffer);
        device.read(0, 4, buffer) catch |err| {
            logger.err("Failed to read from device: {s}", .{@errorName(err)});
            return;
        };
        @import("debug.zig").memory_dump(@intFromPtr(buffer.ptr), @intFromPtr(buffer.ptr) + 2048, .Offset);
    } else {
        logger.err("Failed to find device \"{s}\"", .{name});
    }
}

pub fn main(_: usize) u8 {
    const benchmark = @import("storage/block/benchmark.zig");

    benchmark.runQuickBenchmark("ram0") catch |err| {
        logger.err("Benchmark failed: {s}", .{@errorName(err)});
    };

    test_device("hda");

    // Start shell
    var shell = DefaultShell.Shell.init(tty.get_reader(), tty.get_writer(), .{}, .{
        .on_init = DefaultShell.on_init,
        .pre_prompt = DefaultShell.pre_process,
    });
    while (true) shell.process_line();
}
