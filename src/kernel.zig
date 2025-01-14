const DefaultShell = @import("shell/default/shell.zig");
const tty = @import("./tty/tty.zig");

const task = @import("task/task.zig");
const wait = @import("task/wait.zig");
const task_set = @import("task/task_set.zig");
const scheduler = @import("task/scheduler.zig");

fn task1() u8 {
    const logger = @import("ft").log.scoped(.task1);
    logger.info("invoked", .{});
    for (0..10) |_| {
        logger.info("tic", .{});
        @import("drivers/pit/pit.zig").sleep(500);
    }
    return 43;
}

fn task2() u8 {
    const logger = @import("ft").log.scoped(.task2);
    logger.info("invoked", .{});
    for (0..10) |_| {
        logger.info("tac", .{});
        @import("drivers/pit/pit.zig").sleep(500);
    }
    return 42;
}

fn test_tasks() void {
    const logger = @import("ft").log.scoped(.test_tasks);
    const kernel = task_set.create_task() catch @panic("Failed to create kernel task");

    _ = task.spawn(task1) catch @panic("Failed to spawn task1");
    _ = task.spawn(task2) catch @panic("Failed to spawn task2");

    var stat: wait.Status = undefined;
    var pid: ?task.TaskDescriptor.Pid = 0;

    pid = wait.wait(kernel.pid, .CHILD, &stat, .{}) catch @panic("Failed to wait for kernel task");
    logger.warn("task {} returned {}", .{ pid, stat.value });

    pid = wait.wait(kernel.pid, .CHILD, &stat, .{}) catch @panic("Failed to wait for kernel task");
    logger.warn("task {} returned {}", .{ pid, stat.value });
}

pub fn main() void {
    test_tasks();

    var shell = DefaultShell.Shell.init(tty.get_reader(), tty.get_writer(), .{}, .{
        .on_init = DefaultShell.on_init,
        .pre_prompt = DefaultShell.pre_process,
    });
    while (true) _ = shell.process_line();
}
