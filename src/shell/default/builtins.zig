const std = @import("std");
const tty = @import("../../tty/tty.zig");
const helpers = @import("helpers.zig");
const utils = @import("../utils.zig");
const CmdError = @import("../Shell.zig").CmdError;
const colors = @import("colors");
const scheduler = @import("../../task/scheduler.zig");
const strerror = @import("../../errno.zig").strerror;

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

pub fn exec(shell: anytype, args: [][]u8) CmdError!void {
    if (args.len != 2) return CmdError.InvalidNumberOfArguments;

    const file_tnode = vfs.resolve(args[1]) catch {
        utils.print_error(shell, "Invalid path: {s} does not exist", .{args[1]});
        return CmdError.OtherError;
    };
    defer file_tnode.release();

    const new_task = @import("../../task/task_set.zig").create_task() catch
        @panic("Failed to create new_task");
    try translate_errno(shell, new_task.exec(file_tnode.inode, &.{}, &.{}));
    utils.waitpid(shell, new_task.pid);
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

/// Read N bytes from a character device and hexdump the result.
/// Usage: charread <name> <count>
pub fn charread(shell: anytype, args: [][]u8) CmdError!void {
    if (args.len != 3) return CmdError.InvalidNumberOfArguments;

    const name = args[1];
    const count = std.fmt.parseInt(usize, args[2], 0) catch return CmdError.InvalidParameter;

    const char_reg = @import("../../device/char/registry.zig");
    const dev = char_reg.get_device_by_name(name) orelse {
        utils.print_error(shell, "No such character device: {s}", .{name});
        return CmdError.OtherError;
    };

    const allocator = @import("../../memory.zig").bigAlloc.allocator();
    const buffer = allocator.alloc(u8, count) catch {
        utils.print_error(shell, "Failed to allocate {d} bytes", .{count});
        return CmdError.OtherError;
    };
    defer allocator.free(buffer);

    // Fill with 0xAA so we can see what the device actually writes
    @memset(buffer, 0xAA);

    const bytes_read = dev.read(buffer) catch |err| {
        utils.print_error(shell, "Read error: {s}", .{@errorName(err)});
        return CmdError.OtherError;
    };

    shell.print("Read {d} bytes from '{s}' (1:{d}):\n", .{ bytes_read, name, dev.devt.minor });

    if (bytes_read == 0) {
        shell.print("(EOF)\n", .{});
    } else {
        const start_ptr = @intFromPtr(&buffer[0]);
        @import("../../debug.zig").memory_dump(start_ptr, start_ptr + bytes_read, null);
    }
}

/// Write a string to a character device.
/// Usage: charwrite <name> <string>
pub fn charwrite(shell: anytype, args: [][]u8) CmdError!void {
    if (args.len != 3) return CmdError.InvalidNumberOfArguments;

    const name = args[1];
    const data = args[2];

    const char_reg = @import("../../device/char/registry.zig");
    const dev = char_reg.get_device_by_name(name) orelse {
        utils.print_error(shell, "No such character device: {s}", .{name});
        return CmdError.OtherError;
    };

    const bytes_written = dev.write(data) catch |err| {
        utils.print_error(shell, "Write error: {s}", .{@errorName(err)});
        return CmdError.OtherError;
    };

    shell.print("Wrote {d}/{d} bytes to '{s}' (1:{d})\n", .{
        bytes_written,
        data.len,
        name,
        dev.devt.minor,
    });
}

/// List character devices with optional name filter.
/// Usage: lschar [device_name]
pub fn lschar(shell: anytype, args: [][]u8) CmdError!void {
    const char_reg = @import("../../device/char/registry.zig");

    const filter: ?[]const u8 = if (args.len >= 2) args[1] else null;
    char_reg.show_lschar(shell.writer, filter);
}

const ext2 = @import("../../fs/ext2/driver.zig").fs;
const SuperBlock = @import("../../fs/superblock.zig");
const Inode = @import("../../fs/inode.zig");
const vfs = @import("../../fs/vfs.zig");

var cwd = &@import("shell.zig").cwd;
var current_tnode = &@import("shell.zig").current_tnode;

// pub fn mount(shell: anytype, args: [][]u8) CmdError!void {
//     if (args.len != 2) return CmdError.InvalidNumberOfArguments;
//     const allocator = @import("../../memory.zig").smallAlloc.allocator();
//     const part_name = args[1];
//
//     const part = @import("../../block/registry.zig").get_partition_by_name(part_name) orelse {
//         utils.print_error(shell, "No such device", .{});
//         return CmdError.OtherError;
//     };
//     if (!ext2.identify(part)) {
//         utils.print_error(shell, "Not an {s} filesystem", .{ext2.name});
//         return CmdError.OtherError;
//     }
//     sb = ext2.create(part, allocator);
//     current_tnode = sb.?.get_root();
//     cwd = allocator.dupe(u8, "/") catch @panic("OOM");
// }

pub fn pwd(shell: anytype, _: [][]u8) CmdError!void {
    shell.print("{s}\n", .{cwd.*});
}

fn translate_errno(shell: anytype, val: anytype) CmdError!@TypeOf(val catch unreachable) {
    return val catch |e| {
        utils.print_error(shell, "Error: {s}", .{strerror(e)});
        return CmdError.OtherError;
    };
}

pub fn ls(shell: anytype, _: [][]u8) CmdError!void {
    const file = try translate_errno(shell, scheduler.get_current_task().cwd.inode.open());
    defer file.close() catch {};

    var ent: @import("../../fs/file.zig").DirEnt = undefined;
    while (try translate_errno(shell, file.vtable.readdir(file, &ent))) {
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
    cwd.* = std.fs.path.join(allocator, &.{ cwd.*, args[1] }) catch @panic("OOM");
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

    if (file_tnode.inode.mode.type != .Regular) {
        utils.print_error(shell, "Invalid path: {s} is not a regular file", .{args[1]});
        return CmdError.OtherError;
    }

    const file = try translate_errno(shell, file_tnode.inode.open());
    defer file.close() catch {};
    _ = try translate_errno(shell, file.seek(offset, .Set));
    shell.print("{} bytes written\n", .{try translate_errno(shell, file.write(data))});
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

pub fn mount(shell: anytype, args: [][]u8) CmdError!void {
    if (args.len != 3) return CmdError.InvalidNumberOfArguments;

    const device = args[1];
    const mount_point_path = args[2];

    const mount_point = vfs.resolve(mount_point_path) catch {
        utils.print_error(shell, "Cannot resolve {s}", .{mount_point_path});
        return CmdError.OtherError;
    };

    vfs.mount(mount_point, .{ .UUID = device }, .{}) catch |e| {
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

const device_types = @import("../../device/types.zig");

pub fn mknod(shell: anytype, args: [][]u8) CmdError!void {
    if (args.len != 5) return CmdError.InvalidNumberOfArguments;

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
        'b' => dir_tnode.inode.superblock.create_inode(0, 0, .{ .type = .Block }, .{ .Block = .{ .major = major, .minor = minor } }),
        'c' => dir_tnode.inode.superblock.create_inode(0, 0, .{ .type = .Character }, .{ .Character = .{ .major = major, .minor = minor } }),
        else => {
            utils.print_error(shell, "Invalid node type", .{});
            return CmdError.OtherError;
        },
    });
    defer inode.release();

    try translate_errno(shell, dir_tnode.inode.link(filename, inode));
}
