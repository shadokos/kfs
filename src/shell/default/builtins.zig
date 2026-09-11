const std = @import("std");
const tty = @import("../../tty/tty.zig");
const helpers = @import("helpers.zig");
const utils = @import("../utils.zig");
const CmdError = @import("../Shell.zig").CmdError;
const colors = @import("colors");
const scheduler = @import("../../task/scheduler.zig");
const Inode = @import("../../fs/inode.zig");
const vfs = @import("../../fs/vfs.zig");
const strerror = @import("../../errno.zig").strerror;

const cwd = &@import("shell.zig").cwd;

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

pub fn cmd(_: anytype, _: [][]u8) CmdError!void {
    utils.print_cmd();
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
    const km = @import("../../drivers/input/keyboard/keymap.zig");
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
    const t = @import("../../drivers/tty/themes.zig");
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
            const selected = t.get_theme(args[1]) orelse return CmdError.InvalidParameter;
            if (@import("../../drivers/tty/vt_console.zig").from(tty.get_tty())) |console|
                console.set_theme(selected);
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
        @import("../../timer.zig").busy_sleep(1000);
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
        "io",
        "ctty",
        "jobctl",
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
            // A job of its own, so that the terminal can signal it without
            // reaching the shell that started it.
            new_task.pgid = new_task.pid;
            utils.attach_standard_streams(new_task) catch |e|
                utils.print_error(shell, "no standard streams: {s}", .{@errorName(e)});

            const previous = utils.foreground(new_task);
            defer utils.restore_foreground(previous);

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

pub fn pci(shell: anytype, args: [][]u8) CmdError!void {
    const _pci = @import("../../drivers/pci/pci.zig");

    return switch (args.len) {
        1 => {
            // List all PCI devices
            printk("PCI Devices:\n", .{});
            for (_pci.get_devices()) |device| {
                printk("- 0x{x:0>4} {}:{}.{} {s}\n", .{
                    device.device_id,
                    device.bus,
                    device.device,
                    device.function,
                    @tagName(device.class_code),
                });
            }
        },
        4 => b: {
            // Show information about a specific PCI device
            const bus = std.fmt.parseInt(u8, args[1], 0) catch break :b CmdError.InvalidParameter;
            const dev = std.fmt.parseInt(u8, args[2], 0) catch break :b CmdError.InvalidParameter;
            const func = std.fmt.parseInt(u8, args[3], 0) catch break :b CmdError.InvalidParameter;
            const device = _pci.get_device(bus, dev, func) orelse {
                utils.print_error(shell, "No device found ({}:{}.{})", .{ bus, dev, func });
                break :b CmdError.InvalidParameter;
            };
            device.printInfo(shell.writer);
        },
        else => CmdError.InvalidNumberOfArguments,
    };
}

pub fn devices(shell: anytype, _: [][]u8) CmdError!void {
    const block = @import("../../device/block/registry.zig");
    const char = @import("../../device/char/registry.zig");

    char.show_char_dev(shell.writer);
    _ = shell.writer.write("\n") catch {};

    block.show_block_dev(shell.writer);
}

pub fn partitions(shell: anytype, _: [][]u8) CmdError!void {
    const block = @import("../../device/block/registry.zig");

    block.show_partitions(shell.writer);
}

pub fn lsblk(shell: anytype, args: [][]u8) CmdError!void {
    const block = @import("../../device/block/registry.zig");

    // lsblk [device_name]
    const filter: ?[]const u8 = if (args.len >= 2) args[1] else null;
    block.show_lsblk(shell.writer, filter);
}

pub fn lookup_devt(shell: anytype, args: [][]u8) CmdError!void {
    if (args.len != 3) return CmdError.InvalidNumberOfArguments;

    const name = args[1];
    const partno = std.fmt.parseInt(u32, args[2], 0) catch return CmdError.InvalidParameter;

    const devt = @import("../../device/block/registry.zig").lookup_devt(name, @truncate(partno)) orelse {
        utils.print_error(shell, "No such device", .{});
        return CmdError.OtherError;
    };
    const udev_t = @import("../../device/types.zig").udev_t;
    shell.print("{d} ({d}:{d})\n", .{ @as(udev_t, @bitCast(devt)), devt.major, devt.minor });
}

// Hexdump a block device content with a given start and count
// args: [1] = name, [2] = start, [3] count
pub fn blkread(shell: anytype, args: [][]u8) CmdError!void {
    if (args.len != 4) return CmdError.InvalidNumberOfArguments;
    const name = args[1];
    const start = std.fmt.parseInt(u32, args[2], 0) catch return CmdError.InvalidParameter;
    const count = std.fmt.parseInt(u32, args[3], 0) catch return CmdError.InvalidParameter;

    const block_size = @import("../../device/block/block.zig").STANDARD_BLOCK_SIZE;

    const part = @import("../../device/block/registry.zig").get_partition_by_name(name) orelse {
        utils.print_error(shell, "No such device", .{});
        return CmdError.OtherError;
    };

    const allocator = @import("../../memory.zig").bigAlloc.allocator();
    const buffer = allocator.alloc(u8, @as(usize, count) * block_size) catch {
        utils.print_error(shell, "Failed to allocate memory", .{});
        return CmdError.OtherError;
    };
    @memset(buffer, 0x66);
    defer allocator.free(buffer);

    part.read(start, count, buffer) catch |e| {
        utils.print_error(shell, "Read error: {s}", .{@errorName(e)});
        return CmdError.OtherError;
    };

    const start_ptr = @intFromPtr(&buffer[0]);
    const end_ptr = start_ptr + buffer.len;
    @import("../../debug.zig").memory_dump(start_ptr, end_ptr, start_ptr - (start * block_size));
}

/// List character devices with optional name filter.
/// Usage: lschar [device_name]
pub fn lschar(shell: anytype, args: [][]u8) CmdError!void {
    const char_reg = @import("../../device/char/registry.zig");

    const filter: ?[]const u8 = if (args.len >= 2) args[1] else null;
    char_reg.show_lschar(shell.writer, filter);
}

pub fn pwd(shell: anytype, _: [][]u8) CmdError!void {
    shell.print("{s}\n", .{cwd.*});
}

fn translate_errno(shell: anytype, val: anytype) CmdError!@TypeOf(val catch unreachable) {
    return val catch |e| {
        utils.print_error(shell, "Error: {s}", .{strerror(e)});
        return CmdError.OtherError;
    };
}

pub fn ls(shell: anytype, args: [][]u8) CmdError!void {
    if (args.len > 2) return CmdError.InvalidNumberOfArguments;

    const path = if (args.len == 2) args[1] else ".";
    const tnode = vfs.resolve(path) catch {
        utils.print_error(shell, "Invalid path: {s} does not exist", .{path});
        return CmdError.OtherError;
    };

    const file = try translate_errno(shell, tnode.inode.open());
    defer file.close() catch {};

    var ent: @import("../../fs/file.zig").DirEnt = undefined;
    while (try translate_errno(shell, file.readdir(&ent))) {
        shell.print("{: <10} {s: <10} {s}\n", .{ ent.inode, @tagName(ent.type), ent.name[0..ent.name_len] });
    }
}

pub fn cd(shell: anytype, args: [][]u8) CmdError!void {
    if (args.len != 2) return CmdError.InvalidNumberOfArguments;
    const allocator = @import("../../memory.zig").smallAlloc.allocator();

    const new_tnode = vfs.resolve(args[1]) catch {
        utils.print_error(shell, "Invalid path: {s} does not exist", .{args[1]});
        return CmdError.OtherError;
    };
    if (new_tnode.inode.mode.type != .Directory) {
        utils.print_error(shell, "Invalid path: {s}: Not a directory", .{args[1]});
        return CmdError.OtherError;
    }
    scheduler.get_current_task().chdir(new_tnode);
    new_tnode.release();

    const tmp = cwd.*;
    cwd.* = std.fs.path.resolve(allocator, &.{ cwd.*, args[1] }) catch @panic("OOM");
    allocator.free(tmp);
}

pub fn cat(shell: anytype, args: [][]u8) CmdError!void {
    if (args.len != 2) return CmdError.InvalidNumberOfArguments;

    const file_tnode = vfs.resolve(args[1]) catch {
        utils.print_error(shell, "Invalid path: {s} does not exist", .{args[1]});
        return CmdError.OtherError;
    };
    defer file_tnode.release();
    if (file_tnode.inode.mode.type == .Directory) {
        utils.print_error(shell, "Invalid path: {s} is a directory", .{args[1]});
        return CmdError.OtherError;
    }

    const file = try translate_errno(shell, file_tnode.inode.open());
    defer file.close() catch {};
    var buffer: [512]u8 = undefined;
    var read_size: usize = undefined;

    read_size = try translate_errno(shell, file.read(buffer[0..]));
    while (read_size != 0) {
        std.mem.replaceScalar(u8, buffer[0..], 0, 219);
        shell.print("{s}", .{buffer[0..read_size]});
        read_size = try translate_errno(shell, file.read(buffer[0..]));
    }
}

pub fn readlink(shell: anytype, args: [][]u8) CmdError!void {
    if (args.len != 2) return CmdError.InvalidNumberOfArguments;

    const file_tnode = vfs.resolve(args[1]) catch {
        utils.print_error(shell, "Invalid path: {s} does not exist", .{args[1]});
        return CmdError.OtherError;
    };
    defer file_tnode.release();
    if (file_tnode.inode.mode.type != .Link) {
        utils.print_error(shell, "Invalid path: {s} is not a symlink", .{args[1]});
        return CmdError.OtherError;
    }
    shell.print("{s}\n", .{file_tnode.inode.type_specific.Link});
}

pub fn write(shell: anytype, args: [][]u8) CmdError!void {
    if (args.len != 3) return CmdError.InvalidNumberOfArguments;

    const data = args[2];
    const file_tnode = vfs.resolve(args[1]) catch {
        utils.print_error(shell, "Invalid path: {s} does not exist", .{args[1]});
        return CmdError.OtherError;
    };

    switch (file_tnode.inode.mode.type) {
        .Regular, .Fifo, .Character => {},
        else => {
            utils.print_error(shell, "Invalid path: {s} cannot be written to", .{args[1]});
            return CmdError.OtherError;
        },
    }

    const file = try translate_errno(shell, file_tnode.inode.open());
    defer file.close() catch {};
    shell.print("{} bytes written\n", .{try translate_errno(shell, file.write(data))});
}

pub fn pwrite(shell: anytype, args: [][]u8) CmdError!void {
    if (args.len != 4) return CmdError.InvalidNumberOfArguments;

    const offset = std.fmt.parseInt(usize, args[3], 0) catch {
        utils.print_error(shell, "Invalid offset", .{});
        return CmdError.OtherError;
    };
    const data = args[2];
    const file_tnode = vfs.resolve(args[1]) catch {
        utils.print_error(shell, "Invalid path: {s} does not exist", .{args[1]});
        return CmdError.OtherError;
    };

    if (file_tnode.inode.mode.type != .Regular and file_tnode.inode.mode.type != .Fifo) {
        utils.print_error(shell, "Invalid path: {s} is not a regular file", .{args[1]});
        return CmdError.OtherError;
    }

    const file = try translate_errno(shell, file_tnode.inode.open());
    defer file.close() catch {};
    shell.print("{} bytes written\n", .{try translate_errno(shell, file.pwrite(offset, data))});
}

pub fn stat(shell: anytype, args: [][]u8) CmdError!void {
    if (args.len != 2) return CmdError.InvalidNumberOfArguments;

    const file_tnode = vfs.resolve(args[1]) catch {
        utils.print_error(shell, "Invalid path: {s} does not exist", .{args[1]});
        return CmdError.OtherError;
    };
    defer file_tnode.release();
    std.log.debug("stat tnode: {*}", .{file_tnode});
    shell.print("inode: {}\n", .{file_tnode.inode.ino});
    shell.print("type: {}\n", .{file_tnode.inode.mode.type});
    shell.print("size: {}\n", .{file_tnode.inode.size});
    shell.print("hardlinks: {}\n", .{file_tnode.inode.hard_links});
}

pub fn truncate(shell: anytype, args: [][]u8) CmdError!void {
    if (args.len != 3) return CmdError.InvalidNumberOfArguments;

    const file_tnode = vfs.resolve(args[1]) catch {
        utils.print_error(shell, "Invalid path: {s} does not exist", .{args[1]});
        return CmdError.OtherError;
    };
    defer file_tnode.release();
    if (file_tnode.inode.mode.type != .Regular) {
        utils.print_error(shell, "Invalid path: {s} is not a regular file", .{args[1]});
        return CmdError.OtherError;
    }

    const offset = std.fmt.parseInt(u64, args[2], 0) catch {
        utils.print_error(shell, "Invalid size", .{});
        return CmdError.OtherError;
    };

    try translate_errno(shell, file_tnode.inode.truncate(offset));
}

pub fn unlink(shell: anytype, args: [][]u8) CmdError!void {
    if (args.len != 2) return CmdError.InvalidNumberOfArguments;
    const path = args[1];
    const dirname = std.fs.path.dirnamePosix(path) orelse if (std.fs.path.isAbsolute(path)) {
        utils.print_error(shell, "Cannot unlink root", .{});
        return CmdError.OtherError;
    } else ".";
    const filename = std.fs.path.basenamePosix(path);
    const dir_tnode = vfs.resolve(dirname) catch {
        utils.print_error(shell, "Cannot resolve {s}", .{dirname});
        return CmdError.OtherError;
    };
    defer dir_tnode.release();
    try translate_errno(shell, dir_tnode.inode.unlink(filename));
}

pub fn link(shell: anytype, args: [][]u8) CmdError!void {
    if (args.len != 3) return CmdError.InvalidNumberOfArguments;

    const old_path = args[1];
    const old_dirname = std.fs.path.dirnamePosix(old_path) orelse if (std.fs.path.isAbsolute(old_path)) {
        utils.print_error(shell, "Cannot unlink root", .{});
        return CmdError.OtherError;
    } else ".";
    const old_dir_tnode = vfs.resolve(old_dirname) catch {
        utils.print_error(shell, "Cannot resolve {s}", .{old_dirname});
        return CmdError.OtherError;
    };

    const new_path = args[2];
    const new_dirname = std.fs.path.dirnamePosix(new_path) orelse if (std.fs.path.isAbsolute(new_path)) {
        utils.print_error(shell, "Cannot unlink root", .{});
        return CmdError.OtherError;
    } else ".";
    const new_filename = std.fs.path.basenamePosix(new_path);
    const new_dir_tnode = vfs.resolve(new_dirname) catch {
        utils.print_error(shell, "Cannot resolve {s}", .{new_dirname});
        return CmdError.OtherError;
    };

    try translate_errno(shell, old_dir_tnode.inode.link(new_filename, new_dir_tnode.inode));
}

pub fn flush_fs(shell: anytype, args: [][]u8) CmdError!void {
    if (args.len != 2) return CmdError.InvalidNumberOfArguments;

    const file_tnode = vfs.resolve(args[1]) catch {
        utils.print_error(shell, "Invalid path: {s} does not exist", .{args[1]});
        return CmdError.OtherError;
    };
    defer file_tnode.release();
    try translate_errno(shell, file_tnode.inode.superblock.flush_all());
}

pub fn evict_fs(shell: anytype, args: [][]u8) CmdError!void {
    if (args.len != 2) return CmdError.InvalidNumberOfArguments;

    const file_tnode = vfs.resolve(args[1]) catch {
        utils.print_error(shell, "Invalid path: {s} does not exist", .{args[1]});
        return CmdError.OtherError;
    };
    defer file_tnode.release();
    try translate_errno(shell, file_tnode.inode.superblock.release_all());
}

pub fn statfs(shell: anytype, args: [][]u8) CmdError!void {
    if (args.len != 2) return CmdError.InvalidNumberOfArguments;

    const file_tnode = vfs.resolve(args[1]) catch {
        utils.print_error(shell, "Invalid path: {s} does not exist", .{args[1]});
        return CmdError.OtherError;
    };
    defer file_tnode.release();
    const superblock = file_tnode.inode.superblock;

    shell.print(
        \\  File: "{[File]s}"
        \\    ID: {[ID]?x} Namelen: {[Namelen]d:<7} Type: TODO
        \\Block size: {[BlockSize]d:<10} Fundamental block size: {[FundamentalBlockSize]d}
        \\Blocks: Total: {[BlocksTotal]d:<10} Free: {[BlockFree]:<10} Available: {[BlockAvailable]d}
        \\Inodes: Total: {[InodesTotal]d:<10} Free: {[InodesFree]}
    , .{
        .File = file_tnode.name,
        .ID = superblock.fsid,
        .Namelen = superblock.max_name,
        .BlockSize = superblock.block_size,
        .FundamentalBlockSize = superblock.fragment_size,
        .BlocksTotal = superblock.blocks,
        .BlockFree = superblock.free_blocks,
        .BlockAvailable = superblock.free_blocks - superblock.reserved_blocks,
        .InodesTotal = superblock.files,
        .InodesFree = superblock.free_files,
    });
}

pub fn mknod(shell: anytype, args: [][]u8) CmdError!void {
    if (args.len != 5) return CmdError.InvalidNumberOfArguments;

    const device_types = @import("../../device/types.zig");

    const path = args[1];
    const dirname = std.fs.path.dirnamePosix(path) orelse if (std.fs.path.isAbsolute(path)) {
        utils.print_error(shell, "Cannot unlink root", .{});
        return CmdError.OtherError;
    } else ".";
    const filename = std.fs.path.basenamePosix(path);
    const dir_tnode = vfs.resolve(dirname) catch {
        utils.print_error(shell, "Cannot resolve {s}", .{dirname});
        return CmdError.OtherError;
    };
    defer dir_tnode.release();

    if (args[2].len > 1) {
        utils.print_error(shell, "Invalid node type", .{});
        return CmdError.OtherError;
    }

    const major = std.fmt.parseInt(device_types.major_t, args[3], 0) catch {
        utils.print_error(shell, "Invalid major", .{});
        return CmdError.OtherError;
    };

    const minor = std.fmt.parseInt(device_types.minor_t, args[4], 0) catch {
        utils.print_error(shell, "Invalid minor", .{});
        return CmdError.OtherError;
    };

    const inode = try translate_errno(shell, switch (args[2][0]) {
        'b' => dir_tnode.inode.superblock.create_inode(0, 0, .{ .type = .Block }, .{
            .Block = .{ .major = major, .minor = minor },
        }),
        'c' => dir_tnode.inode.superblock.create_inode(0, 0, .{ .type = .Character }, .{ .Character = .{
            .major = major,
            .minor = minor,
        } }),
        else => {
            utils.print_error(shell, "Invalid node type", .{});
            return CmdError.OtherError;
        },
    });
    defer inode.release();

    try translate_errno(shell, dir_tnode.inode.link(filename, inode));
}

pub fn mount(shell: anytype, args: [][]u8) CmdError!void {
    if (args.len < 3 or args.len > 4) return CmdError.InvalidNumberOfArguments;

    const device = args[1];
    const mount_point_path = args[2];
    const fsname = if (args.len == 4) args[3] else null;

    const mount_point = vfs.resolve(mount_point_path) catch {
        utils.print_error(shell, "Cannot resolve {s}", .{mount_point_path});
        return CmdError.OtherError;
    };

    var diag: std.zon.parse.Diagnostics = .{};
    const part_identifier = std.zon.parse.fromSlice(vfs.PartIdentifier, @import("../../memory.zig").smallAlloc.allocator(), @ptrCast(device), &diag, .{}) catch {
        utils.print_error(shell, "Couldn't parse device `{s}`: {f}", .{ device, diag });
        return CmdError.InvalidParameter;
    };

    vfs.mount(mount_point, part_identifier, .{ .fs = fsname }) catch |e| {
        utils.print_error(shell, "Cannot mount device: {s}\n", .{@errorName(e)});
        return CmdError.OtherError;
    };
}

pub fn unmount(shell: anytype, args: [][]u8) CmdError!void {
    if (args.len != 2) return CmdError.InvalidNumberOfArguments;

    const mount_point_path = args[1];

    const mount_point = vfs.resolve(mount_point_path) catch {
        utils.print_error(shell, "Cannot resolve {s}", .{mount_point_path});
        return CmdError.OtherError;
    };

    mount_point.unmount();
}

/// Read from this terminal outside canonical mode, to exercise the four MIN and
/// TIME cases of POSIX 11.1.7. Restores the previous settings on the way out.
/// Usage: ttyread <vmin> <vtime> <count>
pub fn ttyread(shell: anytype, args: [][]u8) CmdError!void {
    if (args.len != 4) return CmdError.InvalidNumberOfArguments;

    const termios = @import("../../tty/termios.zig");
    const timer = @import("../../timer.zig");

    const vmin = std.fmt.parseInt(u8, args[1], 0) catch return CmdError.InvalidParameter;
    const vtime = std.fmt.parseInt(u8, args[2], 0) catch return CmdError.InvalidParameter;
    const count = std.fmt.parseInt(usize, args[3], 0) catch return CmdError.InvalidParameter;

    var buffer: [64]u8 = undefined;
    if (count == 0 or count > buffer.len) return CmdError.InvalidParameter;

    const t = tty.get_tty();
    const saved = t.config;
    defer t.set_termios(saved);

    var raw = saved;
    raw.c_lflag.ICANON = false;
    raw.c_cc[@intFromEnum(termios.cc_index.VMIN)] = vmin;
    raw.c_cc[@intFromEnum(termios.cc_index.VTIME)] = vtime;
    t.set_termios(raw);

    shell.print("MIN={d} TIME={d}, reading up to {d} bytes\n", .{ vmin, vtime, count });

    const started = timer.get_utime_since_boot();
    const read = t.read(buffer[0..count]) catch |e| {
        utils.print_error(shell, "read: {s}", .{@errorName(e)});
        return CmdError.OtherError;
    };
    const elapsed = timer.get_utime_since_boot() - started;

    shell.print("\nread {d} bytes in {d} ms:", .{ read, elapsed / 1000 });
    for (buffer[0..read]) |c| shell.print(" {x:0>2}", .{c});
    shell.print("\n", .{});
}

/// Read or change the termios of a terminal, by the path userspace takes.
/// Usage: stty <path> [raw|sane]
pub fn stty(shell: anytype, args: [][]u8) CmdError!void {
    if (args.len < 2 or args.len > 3) return CmdError.InvalidNumberOfArguments;

    const termios = @import("../../tty/termios.zig");
    const control = @import("../../tty/ioctl.zig");

    const tnode = vfs.resolve(args[1]) catch {
        utils.print_error(shell, "Invalid path: {s} does not exist", .{args[1]});
        return CmdError.OtherError;
    };
    defer tnode.release();

    const file = try translate_errno(shell, tnode.inode.open());
    defer file.close() catch {};

    var attr: termios.abi.Termios = undefined;
    _ = try translate_errno(
        shell,
        file.ioctl(@intFromEnum(control.Request.TCGETS), @intFromPtr(&attr)),
    );

    if (args.len == 3) {
        if (std.mem.eql(u8, args[2], "raw")) {
            attr.c_lflag.ICANON = false;
            attr.c_lflag.ECHO = false;
            attr.c_cc[@intFromEnum(termios.cc_index.VMIN)] = 1;
            attr.c_cc[@intFromEnum(termios.cc_index.VTIME)] = 0;
        } else if (std.mem.eql(u8, args[2], "sane")) {
            attr = termios.to_abi(.{});
        } else if (std.mem.eql(u8, args[2], "nolocal")) {
            // A line with a carrier to lose, so a disconnect means something.
            attr.c_cflag.CLOCAL = false;
        } else if (std.mem.eql(u8, args[2], "local")) {
            attr.c_cflag.CLOCAL = true;
        } else return CmdError.InvalidParameter;

        _ = try translate_errno(
            shell,
            file.ioctl(@intFromEnum(control.Request.TCSETSF), @intFromPtr(&attr)),
        );
    }

    shell.print("iflag {b:0>12} oflag {b:0>8} lflag {b:0>10}\n", .{
        @as(u12, @truncate(@as(u32, @bitCast(attr.c_iflag)))),
        @as(u8, @truncate(@as(u32, @bitCast(attr.c_oflag)))),
        @as(u10, @truncate(@as(u32, @bitCast(attr.c_lflag)))),
    });
    shell.print("icanon {} echo {} isig {} vmin {d} vtime {d}\n", .{
        attr.c_lflag.ICANON,
        attr.c_lflag.ECHO,
        attr.c_lflag.ISIG,
        attr.c_cc[@intFromEnum(termios.cc_index.VMIN)],
        attr.c_cc[@intFromEnum(termios.cc_index.VTIME)],
    });
}

/// Show the session and process group of a task, and the terminal the session
/// controls. Zero, or no argument, means the shell itself.
/// Usage: session [pid]
pub fn session(shell: anytype, args: [][]u8) CmdError!void {
    if (args.len > 2) return CmdError.InvalidNumberOfArguments;

    const task_set = @import("../../task/task_set.zig");
    const pid = if (args.len == 2)
        std.fmt.parseInt(i32, args[1], 0) catch return CmdError.InvalidParameter
    else
        0;

    const task = if (pid == 0)
        scheduler.get_current_task()
    else
        task_set.get_task_descriptor(pid) orelse {
            utils.print_error(shell, "No such task: {d}", .{pid});
            return CmdError.OtherError;
        };

    shell.print("pid {d} pgid {d} sid {d}", .{ task.pid, task.pgid, task.session.sid });
    if (task.session.ctty) |terminal| {
        shell.print(" ctty tty{d} fg {?d}\n", .{ terminal.index, terminal.foreground_pgid });
    } else {
        shell.print(" no controlling terminal\n", .{});
    }
}

/// Start a session, POSIX setsid. The shell keeps it: a terminal opened
/// afterwards becomes its controlling terminal.
pub fn setsid(shell: anytype, _: [][]u8) CmdError!void {
    const sid = @import("../../syscall/setsid.zig").do() catch |e| {
        utils.print_error(shell, "setsid: {s}", .{@errorName(e)});
        return CmdError.OtherError;
    };
    shell.print("session {d}\n", .{sid});
}

/// Open a path through the open syscall, acquiring the controlling terminal as
/// userspace would. Leaves the descriptor open.
/// Usage: ctty <path> [noctty]
pub fn ctty(shell: anytype, args: [][]u8) CmdError!void {
    if (args.len < 2 or args.len > 3) return CmdError.InvalidNumberOfArguments;

    const open = @import("../../syscall/open.zig");

    var path: [256]u8 = undefined;
    if (args[1].len >= path.len) return CmdError.InvalidParameter;
    @memcpy(path[0..args[1].len], args[1]);
    path[args[1].len] = 0;

    const no_ctty = args.len == 3 and std.mem.eql(u8, args[2], "noctty");
    const fd = open.do(@ptrCast(&path), .{
        .openMode = .read_write,
        .no_controlling_tty = no_ctty,
    }, .{}) catch |e| {
        utils.print_error(shell, "open: {s}", .{@errorName(e)});
        return CmdError.OtherError;
    };
    shell.print("fd {d}\n", .{fd});
}

/// Send a control request to an open path, as userspace reaches tcgetsid.
/// Usage: tioctl <path> <sid|notty|sctty>
pub fn tioctl(shell: anytype, args: [][]u8) CmdError!void {
    if (args.len != 3) return CmdError.InvalidNumberOfArguments;

    const control = @import("../../tty/ioctl.zig");

    const tnode = vfs.resolve(args[1]) catch {
        utils.print_error(shell, "Invalid path: {s} does not exist", .{args[1]});
        return CmdError.OtherError;
    };
    defer tnode.release();

    const file = try translate_errno(shell, tnode.inode.open());
    defer file.close() catch {};

    var sid: i32 = -1;
    const request: control.Request = if (std.mem.eql(u8, args[2], "sid"))
        .TIOCGSID
    else if (std.mem.eql(u8, args[2], "notty"))
        .TIOCNOTTY
    else if (std.mem.eql(u8, args[2], "sctty"))
        .TIOCSCTTY
    else
        return CmdError.InvalidParameter;

    _ = try translate_errno(
        shell,
        file.ioctl(@intFromEnum(request), @intFromPtr(&sid)),
    );
    if (request == .TIOCGSID) shell.print("sid {d}\n", .{sid});
}

/// Drop the line on a terminal, to exercise POSIX 11.1.10 without a modem.
/// Usage: hangup <path>
pub fn hangup(shell: anytype, args: [][]u8) CmdError!void {
    if (args.len != 2) return CmdError.InvalidNumberOfArguments;

    const tnode = vfs.resolve(args[1]) catch {
        utils.print_error(shell, "Invalid path: {s} does not exist", .{args[1]});
        return CmdError.OtherError;
    };
    defer tnode.release();

    const file = try translate_errno(shell, tnode.inode.open());
    defer file.close() catch {};

    const terminal = @import("../../drivers/tty/tty_cdev.zig").terminal_of(file) orelse {
        utils.print_error(shell, "{s} is not a terminal", .{args[1]});
        return CmdError.OtherError;
    };

    terminal.hangup();
    shell.print("tty{d} hung up: {}\n", .{ terminal.index, terminal.hung_up });
}

// test_load_entry is not a CLI builtin, it's used by test_elf to spawn a new task that loads an ELF file and
// reports back the loaded regions and entrypoint. All shell printing happens back in test_elf, after waitpid()
const RegionInfo = struct { begin: usize, end: usize, r: bool, w: bool };
const TestLoadResult = union(enum) {
    ok: struct { entry: usize, phdr_vaddr: usize, regions: []RegionInfo },
    err: @import("../../task/elf.zig").Error,
};
const TestLoadRequest = struct { data: []u8, result: TestLoadResult = undefined };
fn test_load_entry(data_ptr: usize) u8 {
    const heapAlloc = @import("../../memory.zig").bigAlloc.allocator();
    const smallAlloc = @import("../../memory.zig").smallAlloc.allocator();
    const Elf = @import("../../task/elf.zig");
    const RegionSet = @import("../../memory/region_set.zig").RegionSet;
    const task = @import("../../task/task.zig");
    const paging = @import("../../memory/paging.zig");

    const req: *TestLoadRequest = @ptrFromInt(data_ptr);
    const data = req.data;

    const self = @import("../../task/scheduler.zig").get_current_task();
    self.init_vm() catch {
        heapAlloc.free(data);
        req.result = .{ .err = error.LoadFailed };
        task.exit(1);
    };
    const vm = self.vm.?;

    const image = Elf.load(vm, data) catch |e| {
        heapAlloc.free(data);
        req.result = .{ .err = e };
        task.exit(1);
    };

    heapAlloc.free(data); // fully consumed: load() already copied every PT_LOAD's bytes into vm

    var count: usize = 0;
    var it = vm.regions.list.first;
    while (it) |node| : (it = node.next) count += 1;

    const regions = smallAlloc.alloc(RegionInfo, count) catch @panic("oom collecting regions");
    it = vm.regions.list.first;
    var i: usize = 0;
    while (it) |node| : ({
        it = node.next;
        i += 1;
    }) {
        const r = &@as(*RegionSet.ListNode, @fieldParentPtr("node", node)).data;
        regions[i] = .{
            .begin = r.begin * paging.page_size,
            .end = (r.begin + r.len) * paging.page_size,
            .r = r.flags.read,
            .w = r.flags.write,
        };
    }

    req.result = .{ .ok = .{ .entry = image.entry, .phdr_vaddr = image.phdr_vaddr, .regions = regions } };
    task.exit(0);
}

pub fn test_elf(shell: anytype, args: [][]u8) CmdError!void {
    const heapAlloc = @import("../../memory.zig").bigAlloc.allocator();
    const smallAlloc = @import("../../memory.zig").smallAlloc.allocator();
    const Elf = @import("../../task/elf.zig");
    if (args.len < 2) return CmdError.InvalidNumberOfArguments;

    const tnode = vfs.resolve(args[1]) catch return CmdError.OtherError;
    defer tnode.release();
    const data = heapAlloc.alloc(
        u8,
        std.math.cast(usize, tnode.inode.size) orelse return CmdError.OtherError,
    ) catch return CmdError.OtherError;
    errdefer heapAlloc.free(data);

    const file = tnode.inode.open() catch return CmdError.OtherError;
    defer file.close() catch {};

    if ((file.pread(0, data) catch return CmdError.OtherError) != data.len)
        return CmdError.OtherError;

    Elf.validate(data) catch |e| {
        utils.print_error(shell, "Invalid ELF file: {s}", .{@errorName(e)});
        return CmdError.OtherError;
    };

    shell.writer.print("ELF file {s} is valid\n", .{args[1]}) catch {};

    // Create a task to load the elf and print the mapped regions
    const req = smallAlloc.create(TestLoadRequest) catch return CmdError.OtherError;
    defer smallAlloc.destroy(req);
    req.* = .{ .data = data };

    const new_task = @import("../../task/task_set.zig").create_task() catch @panic("cannot create task");
    new_task.spawn(&test_load_entry, @intFromPtr(req)) catch @panic("spawn failed");
    utils.waitpid(shell, new_task.pid);

    switch (req.result) {
        .ok => |ok| {
            defer smallAlloc.free(ok.regions);
            shell.writer.print("entry=0x{x} phdr_vaddr=0x{x}\n", .{ ok.entry, ok.phdr_vaddr }) catch {};
            for (ok.regions) |r| {
                shell.writer.print("region [0x{x}, 0x{x}) r={} w={}\n", .{ r.begin, r.end, r.r, r.w }) catch {};
            }
        },
        .err => |e| {
            utils.print_error(shell, "load failed: {s}", .{@errorName(e)});
        },
    }
}
