const DefaultShell = @import("shell/default/shell.zig");
const tty = @import("./tty/tty.zig");

const task = @import("task/task.zig");
const wait = @import("task/wait.zig");
const task_set = @import("task/task_set.zig");
const scheduler = @import("task/scheduler.zig");

fn task1() u8 {
    const logger = @import("ft/ft.zig").log.scoped(.task1);
    logger.info("invoked", .{});
    for (0..5) |_| {
        logger.info("tic", .{});
        for (0..100_000_000) |_| asm volatile ("nop");
        scheduler.schedule();
    }
    return 43;
}

fn task2() u8 {
    const logger = @import("ft/ft.zig").log.scoped(.task2);
    logger.info("invoked", .{});
    scheduler.schedule();
    for (0..5) |_| {
        logger.info("tac", .{});
        for (0..100_000_000) |_| asm volatile ("nop");
        scheduler.schedule();
    }
    return 42;
}

pub fn main() void {
    const logger = @import("ft/ft.zig").log.scoped(.main);
    task.TaskUnion.init_cache() catch @panic("Failed to initialized kernel_task cache");

    const kernel = task_set.create_task() catch @panic("c'est  la  panique 2");

    const c1 = task.spawn(task1) catch @panic("c'est  la  panique 3");
    const c2 = task.spawn(task2) catch @panic("c'est  la  panique 4");

    for (0..1000) |_| {
        scheduler.schedule();
    }

    var stat: wait.Status = undefined;
    _ = wait.wait(kernel.pid, .CHILD, &stat, .{}) catch @panic("c'est  la  panique 4");
    logger.warn("task 1 returned", .{});
    _ = wait.wait(kernel.pid, .CHILD, &stat, .{}) catch @panic("c'est  la  panique 5");
    logger.warn("task 2 returned", .{});
    // _ = kernel;
    _ = c1;
    _ = c2;
    // _ = logger;

    var shell = DefaultShell.Shell.init(tty.get_reader(), tty.get_writer(), .{}, .{
        .on_init = DefaultShell.on_init,
        .pre_prompt = DefaultShell.pre_process,
    });
    while (true) _ = shell.process_line();
}
