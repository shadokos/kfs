const DefaultShell = @import("shell/default/shell.zig");
const tty = @import("./tty/tty.zig");

pub fn main(_: usize) u8 {
    for (0..tty.max_tty + 1) |i| {
        spawn_shell_on_tty(@intCast(i)) catch |err| {
            @import("ft").log.err("Failed to spawn shell on tty{}: {s}", .{ i, @errorName(err) });
        };
    }
    return 0;
}

fn spawn_shell_on_tty(tty_index: u8) !void {
    const task_set = @import("task/task_set.zig");
    const new_task = try task_set.create_task();

    try new_task.assign_tty(tty_index);

    const ShellArgs = struct {
        tty_index: u8,

        fn shell_main(data: usize) u8 {
            const self: *@This() = @ptrFromInt(data);
            const tty_idx = self.tty_index;

            var shell = DefaultShell.Shell.init(
                (&tty.tty_array[tty_idx]).reader().any(),
                (&tty.tty_array[tty_idx]).writer().any(),
                .{},
                .{
                    .on_init = DefaultShell.on_init,
                    .pre_prompt = DefaultShell.pre_process,
                },
                tty_idx,
            );

            shell.print("Shell started on TTY{}\n", .{tty_idx});

            while (true) shell.process_line();
        }
    };

    const args = try @import("memory.zig").smallAlloc.allocator().create(ShellArgs);
    args.* = .{ .tty_index = tty_index };

    try new_task.spawn(&ShellArgs.shell_main, @intFromPtr(args));
}
