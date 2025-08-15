const std = @import("std");
const DefaultShell = @import("shell/default/shell.zig");
const tty = @import("./tty/tty.zig");
// const ide = @import("./drivers/ide/ide.zig");
const timer = @import("timer.zig");
const logger = std.log.scoped(.main);

pub fn main(_: usize) u8 {
    // demoStorageCapabilities() catch {};

    const benchmark = @import("storage/benchmark.zig");

    // Benchmark de tous les drives
    benchmark.runQuickBenchmark("hda") catch |err| {
        logger.err("Benchmark failed: {s}", .{@errorName(err)});
    };

    benchmark.runQuickBenchmark("cd1") catch |err| {
        logger.err("Benchmark failed: {s}", .{@errorName(err)});
    };

    // Start shell
    var shell = DefaultShell.Shell.init(tty.get_reader(), tty.get_writer(), .{}, .{
        .on_init = DefaultShell.on_init,
        .pre_prompt = DefaultShell.pre_process,
    });
    while (true) shell.process_line();
}
