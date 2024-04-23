const DefaultShell = @import("shell/default/shell.zig");
const tty = @import("./tty/tty.zig");

const task = @import("task/task.zig");
const task_set = @import("task/task_set.zig");
const scheduler = @import("task/scheduler.zig");

fn task1() void {
    const logger = @import("ft/ft.zig").log.scoped(.task1);
    logger.info("invoked", .{});
    scheduler.schedule();
    while (true) {
        logger.info("tic", .{});
        for (0..100_000_000) |_| asm volatile ("nop");
        scheduler.schedule();
    }
}

fn task2() void {
    const logger = @import("ft/ft.zig").log.scoped(.task2);
    logger.info("invoked", .{});
    scheduler.schedule();
    while (true) {
        logger.info("tac", .{});
        for (0..100_000_000) |_| asm volatile ("nop");
        scheduler.schedule();
    }
}
pub fn main() void {
    task.TaskUnion.init_cache() catch @panic("Failed to initialized kernel_task cache");

    const kernel = task_set.create_task() catch @panic("c'est  la  panique 2");
    scheduler.add_task(kernel);

    _ = task.spawn(task1) catch @panic("c'est  la  panique 3");
    _ = task.spawn(task2) catch @panic("c'est  la  panique 4");

    while (true) {
        scheduler.schedule();
    }

    var shell = DefaultShell.Shell.init(tty.get_reader(), tty.get_writer(), .{}, .{
        .on_init = DefaultShell.on_init,
        .pre_prompt = DefaultShell.pre_process,
    });
    while (true) _ = shell.process_line();
}
