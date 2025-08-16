const std = @import("std");
const DefaultShell = @import("shell/default/shell.zig");
const tty = @import("./tty/tty.zig");
// const ide = @import("./drivers/ide/ide.zig");
const timer = @import("timer.zig");
const logger = std.log.scoped(.main);

pub fn main(_: usize) u8 {
    // demoStorageCapabilities() catch {};

    const benchmark = @import("storage/benchmark.zig");
    const storage = @import("storage/storage.zig");

    // Benchmark de tous les drives
    // benchmark.runQuickBenchmark("hda") catch |err| {
    //     logger.err("Benchmark failed: {s}", .{@errorName(err)});
    // };

    benchmark.runQuickBenchmark("ram0") catch |err| {
        logger.err("Benchmark failed: {s}", .{@errorName(err)});
    };

    if (storage.findDevice("hda")) |device| {
        logger.info("Found device: {s}", .{device.getName()});
        const allocator = @import("memory.zig").bigAlloc.allocator();
        const buffer = allocator.alloc(u8, 2048) catch |err| {
            logger.err("Failed to allocate buffer: {s}", .{@errorName(err)});
            return 1;
        };
        defer allocator.free(buffer);
        device.read(0, 4, buffer) catch |err| {
            logger.err("Failed to read from device: {s}", .{@errorName(err)});
            return 1;
        };
        @import("debug.zig").memory_dump(@intFromPtr(buffer.ptr), @intFromPtr(buffer.ptr) + 2048, .Offset);
    } else {
        logger.err("Failed to find device cd1", .{});
    }

    // benchmark.runQuickBenchmark("cd1") catch |err| {
    //     logger.err("Benchmark failed: {s}", .{@errorName(err)});
    // };

    // Start shell
    var shell = DefaultShell.Shell.init(tty.get_reader(), tty.get_writer(), .{}, .{
        .on_init = DefaultShell.on_init,
        .pre_prompt = DefaultShell.pre_process,
    });
    while (true) shell.process_line();
}
