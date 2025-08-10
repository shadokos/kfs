const std = @import("std");
const tty = @import("../../tty/tty.zig");
const helpers = @import("helpers.zig");
const utils = @import("../utils.zig");
const CmdError = @import("../Shell.zig").CmdError;
const colors = @import("colors");

// TODO Replace printk with format(shell.writer, format, args)...
// As this builtin definitions are only used with graphic mode, it's ok to use printk for now
const printk = tty.printk;

pub fn stack(_: anytype, _: [][]u8) CmdError!void {
    @import("../../debug.zig").dump_current_stack_trace_verbose() catch {};
}

fn _help_available_commands() void {
    printk(colors.blue ++ "Available commands:\n" ++ colors.reset, .{});
    inline for (@typeInfo(@This()).@"struct".decls) |decl| {
        printk("  - {s}\n", .{decl.name});
    }
}

pub fn help(shell: anytype, data: [][]u8) CmdError!void {
    if (data.len <= 1) {
        _help_available_commands();
        return;
    }
    inline for (@typeInfo(helpers).@"struct".decls) |decl| {
        if (std.mem.eql(u8, decl.name, data[1])) {
            @field(helpers, decl.name)();
            return;
        }
    }
    utils.print_error(shell, "There's no help page for \"{s}\"", .{data[1]});
    _help_available_commands();
    return CmdError.OtherError;
}

pub fn clear(_: anytype, _: [][]u8) CmdError!void {
    printk("\x1b[2J\x1b[H", .{});
    return;
}

pub fn hexdump(_: anytype, args: [][]u8) CmdError!void {
    if (args.len != 3) {
        return CmdError.InvalidNumberOfArguments;
    }
    const begin: usize = std.fmt.parseInt(usize, args[1], 0) catch return CmdError.InvalidParameter;
    const len: usize = std.fmt.parseInt(usize, args[2], 0) catch return CmdError.InvalidParameter;
    @import("../../debug.zig").memory_dump(begin, begin +| len, null);
}

pub fn mmap(_: anytype, _: [][]u8) CmdError!void {
    utils.print_mmap();
}

pub fn elf(_: anytype, _: [][]u8) CmdError!void {
    utils.print_elf();
}

pub fn keymap(_: anytype, args: [][]u8) CmdError!void {
    const km = @import("../../tty/keyboard/keymap.zig");
    switch (args.len) {
        1 => {
            const list = km.keymap_list;
            printk("Installed keymaps:\n\n", .{});
            for (list) |e| {
                printk(" - {s}\n", .{e});
            }
            printk("\n", .{});
        },
        2 => km.set_keymap(args[1]) catch return CmdError.InvalidParameter,
        else => return CmdError.InvalidNumberOfArguments,
    }
}

pub fn theme(_: anytype, args: [][]u8) CmdError!void {
    const t = @import("../../tty/themes.zig");
    switch (args.len) {
        1 => {
            const list = t.theme_list;
            printk("Available themes:\n\n", .{});
            for (list) |e| {
                printk(" - {s}\n", .{e});
            }
            printk("\n", .{});
            printk("Current palette:\n", .{});
            utils.show_palette();
        },
        2 => {
            tty.get_tty().set_theme(t.get_theme(args[1]) orelse return CmdError.InvalidParameter);
            printk("\x1b[2J\x1b[H", .{});
            utils.show_palette();
        },
        else => return CmdError.InvalidNumberOfArguments,
    }
}

pub fn shutdown(shell: anytype, _: [][]u8) CmdError!void {
    @import("../../drivers/acpi/acpi.zig").power_off();
    utils.print_error(shell, "Failed to shutdown", .{});
    return CmdError.OtherError;
}

pub fn reboot(shell: anytype, _: [][]u8) CmdError!void {
    // Try to reboot using PS/2 Controller
    @import("../../drivers/ps2/ps2.zig").cpu_reset();

    // If it fails, try the page fault method
    asm volatile ("jmp 0xFFFF");

    utils.print_error(shell, "Reboot failed", .{});
    return CmdError.OtherError;
}

pub fn pm(_: anytype, _: [][]u8) CmdError!void {
    @import("../../memory.zig").pageFrameAllocator.print();
}

const vpa = &@import("../../memory.zig").kernel_virtual_space;

pub fn alloc_page(shell: anytype, args: [][]u8) CmdError!void {
    if (args.len != 2) return CmdError.InvalidNumberOfArguments;
    const nb = std.fmt.parseInt(usize, args[1], 0) catch return CmdError.InvalidParameter;
    const pages = vpa.alloc_pages(nb) catch {
        utils.print_error(shell, "Failed to allocate {d} pages", .{nb});
        return CmdError.OtherError;
    };
    printk("Allocated {d} pages at 0x{x:0>8}\n", .{ nb, @intFromPtr(pages) });
}

pub fn kmalloc(shell: anytype, args: [][]u8) CmdError!void {
    if (args.len != 2) return CmdError.InvalidNumberOfArguments;
    var kmem = &@import("../../memory.zig").smallAlloc;
    const nb = std.fmt.parseInt(usize, args[1], 0) catch return CmdError.InvalidParameter;
    const obj: []u8 = kmem.alloc(u8, nb) catch {
        utils.print_error(shell, "Failed to allocate {d} bytes", .{nb});
        return CmdError.OtherError;
    };
    printk("Allocated {d} bytes at 0x{x}\n", .{ nb, @intFromPtr(&obj[0]) });
}

pub fn kfree(shell: anytype, args: [][]u8) CmdError!void {
    if (args.len != 2) return CmdError.InvalidNumberOfArguments;

    var kmem = &@import("../../memory.zig").smallAlloc;
    const addr = std.fmt.parseInt(usize, args[1], 0) catch return CmdError.InvalidParameter;
    if (!std.mem.isAligned(addr, @sizeOf(usize))) {
        utils.print_error(shell, "0x{x} is not aligned", .{addr});
        return CmdError.OtherError;
    }
    kmem.free(@as(*usize, @ptrFromInt(addr)));
}

pub fn ksize(shell: anytype, args: [][]u8) CmdError!void {
    if (args.len != 2) return CmdError.InvalidNumberOfArguments;

    var kmem = &@import("../../memory.zig").smallAlloc;
    const addr = std.fmt.parseInt(usize, args[1], 0) catch return CmdError.InvalidParameter;
    if (!std.mem.isAligned(addr, @sizeOf(usize))) {
        utils.print_error(shell, "0x{x} is not aligned", .{addr});
        return CmdError.OtherError;
    }
    const size = kmem.obj_size(@as(*usize, @ptrFromInt(addr))) catch |e| {
        utils.print_error(shell, "Failed to get size of 0x{x}: {s}", .{ addr, @errorName(e) });
        return CmdError.OtherError;
    };
    printk("Size of 0x{x} is {d} bytes\n", .{ addr, size });
}

pub fn krealloc(shell: anytype, args: [][]u8) CmdError!void {
    if (args.len != 3) return CmdError.InvalidNumberOfArguments;

    var kmem = &@import("../../memory.zig").smallAlloc;
    const addr = std.fmt.parseInt(usize, args[1], 0) catch return CmdError.InvalidParameter;
    const new_size = std.fmt.parseInt(usize, args[2], 0) catch return CmdError.InvalidParameter;
    if (!std.mem.isAligned(addr, @sizeOf(usize))) {
        utils.print_error(shell, "0x{x} is not aligned", .{addr});
        return CmdError.OtherError;
    }
    const obj = kmem.realloc(u8, @as([*]u8, @ptrFromInt(addr)), new_size) catch |e| {
        utils.print_error(shell, "Failed to realloc 0x{x}: {s}", .{ addr, @errorName(e) });
        return CmdError.OtherError;
    };
    printk("Realloc 0x{x} to 0x{x} (new_len: {d})\n", .{ addr, @intFromPtr(&obj[0]), obj.len });
}

pub fn slabinfo(_: anytype, _: [][]u8) CmdError!void {
    (&@import("../../memory.zig").globalCache).print();
}

pub fn pfa(_: anytype, _: [][]u8) CmdError!void {
    (&@import("../../memory.zig").pageFrameAllocator).print();
}

pub fn multiboot_info(_: anytype, _: [][]u8) CmdError!void {
    printk("{*}\n", .{@import("../../boot.zig").multiboot_info});
    @import("../../multiboot.zig").list_tags();
}

// TODO: Remove this builtin
// ... For debugging purposes only
pub fn cache_create(_: anytype, args: [][]u8) CmdError!void {
    if (args.len != 4) return CmdError.InvalidNumberOfArguments;
    const globalCache = &@import("../../memory.zig").globalCache;
    const name = args[1];
    const size = std.fmt.parseInt(usize, args[2], 0) catch return CmdError.InvalidParameter;
    const order = std.fmt.parseInt(usize, args[3], 0) catch return CmdError.InvalidParameter;
    const new_cache = globalCache.create(
        name,
        @import("../../memory.zig").directPageAllocator.page_allocator(),

        size,
        @truncate(order),
        @alignOf(usize),
    ) catch {
        printk("Failed to create cache\n", .{});
        return CmdError.OtherError;
    };
    printk("cache allocated: {*}\n", .{new_cache});
}

// // TODO: Remove this builtin
// ... For debugging purposes only
pub fn cache_destroy(_: anytype, args: [][]u8) CmdError!void {
    if (args.len != 2) return CmdError.InvalidNumberOfArguments;

    const globalCache = &@import("../../memory.zig").globalCache;
    const addr = std.fmt.parseInt(usize, args[1], 0) catch return CmdError.InvalidParameter;

    globalCache.destroy(@ptrFromInt(addr));
}

// TODO: Remove this builtin
// ... For debugging purposes only
pub fn shrink(_: anytype, _: [][]u8) CmdError!void {
    const Cache = @import("../../memory/object_allocators/slab/cache.zig").Cache;
    var node: ?*Cache = &@import("../../memory.zig").globalCache.cache;
    while (node) |n| : (node = n.next) n.shrink();
}

pub fn kfuzz(shell: anytype, args: [][]u8) CmdError!void {
    if (args.len < 2) return CmdError.InvalidNumberOfArguments;

    const nb = std.fmt.parseInt(usize, args[1], 0) catch return CmdError.InvalidParameter;
    const max_size = if (args.len == 3) std.fmt.parseInt(
        usize,
        args[2],
        0,
    ) catch return CmdError.InvalidParameter else 10000;

    var buffer: [4096]u8 = undefined;
    return utils.fuzz(
        @import("../../memory.zig").directMemory.allocator(),
        @constCast(&shell.writer.adaptToNewApi(&buffer).new_interface),
        nb,
        max_size,
        false,
    ) catch CmdError.OtherError;
}

pub fn vfuzz(shell: anytype, args: [][]u8) CmdError!void {
    if (args.len < 2) return CmdError.InvalidNumberOfArguments;

    const nb = std.fmt.parseInt(usize, args[1], 0) catch return CmdError.InvalidParameter;
    const max_size = if (args.len == 3) std.fmt.parseInt(
        usize,
        args[2],
        0,
    ) catch return CmdError.InvalidParameter else 10000;

    var buffer: [4096]u8 = undefined;
    return utils.fuzz(
        @import("../../memory.zig").bigAlloc.allocator(),
        @constCast(&shell.writer.adaptToNewApi(&buffer).new_interface),
        nb,
        max_size,
        false,
    ) catch CmdError.OtherError;
}

pub fn sleep(_: anytype, args: [][]u8) CmdError!void {
    if (args.len != 2) return CmdError.InvalidNumberOfArguments;
    const ms = std.fmt.parseInt(u64, args[1], 0) catch return CmdError.InvalidParameter;
    @import("../../task/sleep.zig").sleep(ms) catch {};
}

pub fn wait(shell: anytype, _: [][]u8) CmdError!void {
    var status: @import("../../task/wait.zig").Status = undefined;
    const current_pid = @import("../../task/scheduler.zig").get_current_task().pid;
    const pid = @import("../../task/wait.zig").wait(
        current_pid,
        .CHILD,
        &status,
        null,
        .{
            .WNOHANG = true,
            .WCONTINUED = true,
            .WUNTRACED = true,
        },
    ) catch |e| {
        printk("wait error: {s}", .{@errorName(e)});
        return CmdError.OtherError;
    };
    if (pid == 0)
        return;
    utils.print_status(shell, pid, status);
}

pub fn kill(_: anytype, args: [][]u8) CmdError!void {
    if (args.len != 3) return CmdError.InvalidNumberOfArguments;
    const pid = std.fmt.parseInt(i32, args[1], 0) catch return CmdError.InvalidParameter;
    const signal = std.fmt.parseInt(u32, args[2], 0) catch return CmdError.InvalidParameter;
    @import("../../syscall/kill.zig").do(pid, @enumFromInt(signal)) catch return CmdError.InvalidParameter;
}

pub fn pstree(shell: anytype, _: [][]u8) CmdError!void {
    var prefix: [80]u8 = [1]u8{' '} ** 80;
    utils.pstree(shell, 0, &prefix, 0);
}

pub fn tic(shell: anytype, args: [][]u8) CmdError!void {
    var n = if (args.len == 2) std.fmt.parseInt(i32, args[1], 0) catch return CmdError.InvalidParameter else null;
    while (if (n) |nv| nv > 0 else true) {
        shell.print("tic\n", .{});
        @import("../../drivers/pit/pit.zig").sleep(1000);
        if (n) |*nv| nv.* -= 1;
    }
}

pub fn philo(_: anytype, args: [][]u8) CmdError!void {
    // arg 1: nb philosophers
    // arg 2: time to die
    // arg 3: time to eat
    // arg 4: time to sleep

    if (args.len < 5) return CmdError.InvalidNumberOfArguments;

    const nb_philosophers = std.fmt.parseInt(u8, args[1], 0) catch return CmdError.InvalidParameter;
    const time_to_die = std.fmt.parseInt(usize, args[2], 0) catch return CmdError.InvalidParameter;
    const time_to_eat = std.fmt.parseInt(usize, args[3], 0) catch return CmdError.InvalidParameter;
    const time_to_sleep = std.fmt.parseInt(usize, args[4], 0) catch return CmdError.InvalidParameter;

    @import("../../misc/philosophers.zig").main(
        nb_philosophers,
        time_to_die,
        time_to_eat,
        time_to_sleep,
    );
}

pub fn demo(shell: anytype, args: [][]u8) CmdError!void {
    const array = [_][]const u8{
        "mmap",
        "minitalk",
        "sleep",
        "count",
        "fork",
    };

    if (args.len != 2) {
        shell.print("Available routines:\n", .{});
        for (array) |f| {
            shell.print("- {s}\n", .{f});
        }
        return CmdError.InvalidNumberOfArguments;
    }

    inline for (array) |name| {
        if (std.mem.eql(u8, name, args[1])) {
            const new_task = @import("../../task/task_set.zig").create_task() catch
                @panic("Failed to create new_task");
            new_task.spawn(
                &@import("../../task/userspace.zig").call_userspace,
                @intFromPtr(@extern(?*fn () void, .{ .name = "userland_" ++ name }).?),
            ) catch @panic("Failed to spawn new_task");
            utils.waitpid(shell, new_task.pid);
            return;
        }
    } else {
        return CmdError.InvalidParameter;
    }
}
