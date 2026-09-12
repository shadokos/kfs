const DefaultShell = @import("shell/default/shell.zig");
const tty = @import("./tty/tty.zig");
const CommandLine = @import("command_line.zig");
const vfs = @import("fs/vfs.zig");

pub fn main(_: usize) u8 {


    if (CommandLine.get().root) |root| {
        vfs.mount(vfs.get_hard_root(), root, .{}) catch @panic("Failed to mount root fs.");
    }

    if (CommandLine.get().init) |init| {
        @import("std").log.debug("calling init", .{});
        const allocator = @import("memory.zig").smallAlloc.allocator();
        const slice : [:0]u8 = allocator.allocSentinel(u8, init.len, 0) catch @panic("todo");
        @memcpy(slice, init);
        @import("syscall/execve.zig").do(slice, &.{}, &.{}) catch @import("std").log.debug("cannot exec entrypoint", .{});
    }
    var shell = DefaultShell.Shell.init(tty.get_reader(), tty.get_writer(), .{}, .{
        .on_init = DefaultShell.on_init,
        .pre_prompt = DefaultShell.pre_process,
    });
    while (true) shell.process_line();
}
