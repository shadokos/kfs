const DefaultShell = @import("shell/default/shell.zig");
const tty = @import("./tty/tty.zig");

const task = @import("task/task.zig");
const cpu = @import("cpu.zig");
const wait = @import("task/wait.zeig");
const signal = @import("task/signal.zig");
const mapping = @import("memory/mapping.zig");
const paging = @import("memory/paging.zig");
const task_set = @import("task/task_set.zig");
const scheduler = @import("task/scheduler.zig");

var page: *allowzero align(4096) volatile paging.page = undefined;
var ptr: *volatile u32 = undefined;

fn task1(data: anytype) u8 {
    const i: u32 = data;
    const logger = @import("ft/ft.zig").log.scoped(.task1);
    const current_task = scheduler.get_current_task();
    if (i == 3) {
        task.init_vm(current_task) catch @panic("asdfasdfasdfasd");
        if (current_task.vm) |vm| {
            logger.info("vm: {x:0>8} {}", .{ @intFromPtr(vm), @alignOf(@TypeOf(vm.*)) });
            page = vm.alloc_pages(1) catch |e| {
                logger.err("cannot allocate userspace page {s}", .{@errorName(e)});
                @panic("");
            };
            ptr = @ptrCast(page);
            ptr.* = 42;
        }
    }
    logger.info("{} before value: {}", .{ scheduler.get_current_task().pid, ptr.* });

    scheduler.schedule();
    ptr.* = @intCast(scheduler.get_current_task().pid);

    // while(true) {}
    for (0..i) |_| {
        const new_task = task_set.create_task() catch @panic("c'est  la  panique 4");
        new_task.clone_vm(scheduler.get_current_task()) catch @panic("c'est  la  panique 4");
        new_task.spawn(task1, i - 1) catch @panic("c'est  la  panique 4");
    }
    logger.info("invoked, {}", .{i});
    for (0..5) |_| {
        // logger.info("tic", .{});
        logger.info("{} value: {} ", .{ scheduler.get_current_task().pid, ptr.* });
        // ptr.* = @intCast(scheduler.get_current_task().pid);

        @import("drivers/pit/pit.zig").wait_ms(1000);
    }
    @import("drivers/pit/pit.zig").wait_ms(1000000);
    while (true) {
        // logger.info("tic", .{});
        logger.info("{} {x:0>8} value: {}", .{
            scheduler.get_current_task().pid,
            @intFromPtr(&scheduler.get_current_task().vm.?.directory),
            ptr.*,
        });
        @import("drivers/pit/pit.zig").wait_ms(1000);
    }
    return 43;
}

fn task2(_: anytype) u8 {
    const logger = @import("ft/ft.zig").log.scoped(.task2);
    logger.info("invoked", .{});
    scheduler.schedule();
    for (0..5) |_| {
        // logger.info("tac", .{});
        for (0..100_0) |_| asm volatile ("nop");
        scheduler.schedule();
    }
    return 42;
}

pub fn main() void {
    // const logger = @import("ft/ft.zig").log.scoped(.main);
    task.TaskUnion.init_cache() catch @panic("Failed to initialized kernel_task cache");

    _ = task_set.create_task() catch @panic("c'est  la  panique 2");

    const new_task = task_set.create_task() catch @panic("c'est  la  panique 4");
    new_task.spawn(task.bootstrap, 3) catch @panic("c'est  la  panique 3");

    // const c2 = task.spawn(task2, null) catch @panic("c'est  la  panique 4");
    // const c3 = task.spawn(task3, null) catch @panic("c'est  la  panique 5");

    // for (0..1000) |_| {
    //     scheduler.schedule();
    // }
    //
    // var stat: wait.Status = undefined;
    // _ = wait.wait(kernel.pid, .CHILD, &stat, .{}) catch @panic("c'est  la  panique 4");
    // logger.warn("task 1 returned", .{});
    // _ = wait.wait(kernel.pid, .CHILD, &stat, .{}) catch @panic("c'est  la  panique 5");
    // logger.warn("task 2 returned", .{});
    // logger.info("task3 pid: {}", .{c3.pid});
    // _ = kernel;
    // _ = c1;
    // _ = c2;
    // _ = logger;

    var shell = DefaultShell.Shell.init(tty.get_reader(), tty.get_writer(), .{}, .{
        .on_init = DefaultShell.on_init,
        .pre_prompt = DefaultShell.pre_process,
    });
    while (true) _ = shell.process_line();
}
