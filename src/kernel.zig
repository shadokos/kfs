const DefaultShell = @import("shell/default/shell.zig");
const tty = @import("./tty/tty.zig");

var t: task.TaskUnion = undefined;
var t1: task.TaskUnion = undefined;
var t2: task.TaskUnion = undefined;

fn task1() void {
    const logger = @import("ft/ft.zig").log.scoped(.task1);
    logger.info("invoked", .{});
    task.switch_to_task(&t1, &t);
    while (true) {
        logger.info("tic", .{});
        for (0..100_000_000) |_| asm volatile ("nop");
        task.switch_to_task(&t1, &t2);
    }
}

fn task2() void {
    const logger = @import("ft/ft.zig").log.scoped(.task2);
    logger.info("invoked", .{});
    task.switch_to_task(&t2, &t);
    while (true) {
        logger.info("tac", .{});
        for (0..100_000_000) |_| asm volatile ("nop");
        task.switch_to_task(&t2, &t1);
    }
}

const task = @import("task/process/process.zig");
pub fn main() void {
    task.TaskUnion.init_cache() catch @panic("Failed to initialized kernel_task cache");
    t = task.TaskUnion.init(0, &t, &t);
    task.switch_to_task(&t, &t);

    task.clone(task1, @ptrFromInt(@as(u32, @intFromPtr(&t1.stack)) + t1.stack.len));
    task.clone(task2, @ptrFromInt(@as(u32, @intFromPtr(&t2.stack)) + t2.stack.len));

    task.switch_to_task(&t, &t1);

    var shell = DefaultShell.Shell.init(tty.get_reader(), tty.get_writer(), .{}, .{
        .on_init = DefaultShell.on_init,
        .pre_prompt = DefaultShell.pre_process,
    });
    while (true) _ = shell.process_line();
}
