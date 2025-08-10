const std = @import("std");
const tty = @import("../tty/tty.zig");
const StackIterator = std.debug.StackIterator;

const c = @import("colors");

const prompt: *const [2:0]u8 = "»";
extern var stack_bottom: [*]u8;

pub fn ensure_newline(writer: std.io.AnyWriter) void {
    std.fmt.format(writer, "{s}\x1b[{d}C\r", .{
        c.invert ++ "%" ++ c.reset, // No newline char: '%' character in reverse
        tty.width - 2, // Move cursor to the end of the line or on the next line if the line is not empty
    }) catch {};
}

pub fn print_error(shell: anytype, comptime msg: []const u8, args: anytype) void {
    ensure_newline(shell.writer);
    std.fmt.format(shell.writer, c.red ++ "Error" ++ c.reset ++ ": " ++ msg ++ "\n", args) catch {};
}

pub fn print_prompt(shell: anytype) void {
    ensure_newline(shell.writer);

    // print the prompt:
    // prompt collor depending on the last command status
    std.fmt.format(shell.writer, "{s}{s}" ++ c.reset ++ " ", .{
        if (shell.execution_context.err != null) c.red else c.cyan,
        prompt,
    }) catch {};
}

pub fn memory_dump(start_address: usize, end_address: usize) void {
    const start: usize = @min(start_address, end_address);
    const end: usize = @max(start_address, end_address);

    var i: usize = 0;
    while (start +| i < end) : ({
        i +|= 16;
    }) {
        var ptr: usize = start +| i;
        var offset: usize = 0;
        var offsetPreview: usize = 0;
        var line: [67]u8 = [_]u8{' '} ** 67;

        _ = std.fmt.bufPrint(&line, "{x:0>8}: ", .{start +| i}) catch {};

        while (ptr +| 1 < start +| i +| 16 and ptr < end) : ({
            ptr +|= 2;
            offset += 5;
            offsetPreview += 2;
        }) {
            const byte1: u8 = @as(*allowzero u8, @ptrFromInt(ptr)).*;
            const byte2: u8 = @as(*allowzero u8, @ptrFromInt(ptr +| 1)).*;

            _ = std.fmt.bufPrint(line[10 + offset ..], "{x:0>2}{x:0>2} ", .{ byte1, byte2 }) catch {};
            _ = std.fmt.bufPrint(line[51 + offsetPreview ..], "{s}{s}", .{
                [_]u8{if (std.ascii.isPrint(byte1)) byte1 else '.'},
                [_]u8{if (std.ascii.isPrint(byte2)) byte2 else '.'},
            }) catch {};
        }

        tty.printk("{s}\n", .{line});
    }
}

pub inline fn print_stack() void {
    if (@import("build_options").optimize != .Debug) {
        print_error("{s}", .{"The dump_stack function is only available in debug mode"});
        return;
    }

    const ebp: usize = @frameAddress();
    var esp: usize = 0;
    var si: StackIterator = StackIterator.init(null, ebp);
    var old_fp: usize = 0;
    var link: bool = false;
    var pc: ?usize = null;

    asm volatile ("movl %esp, %[esp]"
        : [esp] "=r" (esp),
    );

    tty.printk("{s}EBP{s}, {s}ESP{s}, {s}PC{s}\n", .{
        c.yellow, c.reset,
        c.red,    c.reset,
        c.blue,   c.reset,
    });
    tty.printk("   ┌" ++ "─" ** 12 ++ "┐ <- {s}0x{x:0>8}{s}\n", .{ c.red, esp, c.reset });
    while (true) {
        var size = si.fp - esp;

        if (pc) |_| size -= @sizeOf(usize);
        if (size > 0)
            tty.printk("{s}│     ...    │ {s}{d}{s} bytes\n{s}{s}", .{
                if (link) "│  " else "   ", c.green,                         size, c.reset,
                if (link) "│  " else "   ", "├" ++ "─" ** 12 ++ "┤\n",
            });
        old_fp = si.fp;
        esp = si.fp + @sizeOf(usize);
        if (si.next()) |addr| {
            pc = addr;
            tty.printk("{s}│ {s}0x{x:0>8}{s} │ <- {s}0x{x:0>8}{s}\n", .{
                if (link) "└> " else "   ",
                c.yellow,
                si.fp,
                c.reset,
                c.yellow,
                old_fp,
                c.reset,
            });
            link = true;
            if (si.fp > @intFromPtr(stack_bottom)) break;
            tty.printk("   └─┬" ++ "─" ** 10 ++ "┘\n", .{});
            tty.printk("┌" ++ "─" ** 4 ++ "┘\n", .{});
            tty.printk("│  ┌" ++ "─" ** 12 ++ "┐\n", .{});
            tty.printk("│  │ {s}0x{x:0>8}{s} │ <- {s}0x{x:0>8}{s}\n", .{
                c.blue, addr, c.reset,
                c.red,  esp,  c.reset,
            });
            tty.printk("│  ├" ++ "─" ** 12 ++ "┤\n", .{});
        } else {
            tty.printk("{s}│ {s}0x{x:0>8}{s} │ <- {s}0x{x:0>8}{s}\n", .{
                if (link) "└> " else "   ",
                c.yellow,
                @as(*align(1) const usize, @ptrFromInt(si.fp)).*,
                c.reset,
                c.yellow,
                si.fp,
                c.reset,
            });
            break;
        }
    }
    tty.printk("   └" ++ "─" ** 12 ++ "┘\n", .{});
}

pub inline fn dump_stack() void {
    if (@import("build_options").optimize != .Debug) {
        print_error("{s}", .{"The dump_stack function is only available in debug mode"});
        return;
    }

    const ebp: usize = @frameAddress();
    var esp: usize = 0;
    var si: StackIterator = StackIterator.init(null, ebp);
    var pc: ?usize = null;

    asm volatile ("movl %esp, %[esp]"
        : [esp] "=r" (esp),
    );

    while (true) {
        const size = si.fp - esp + @sizeOf(usize);

        tty.printk(
            \\{s}STACK FRAME{s}
            \\Size: {s}0x{x}{s} ({s}{d}{s}) bytes
            \\ebp: {s}0x{x}{s}, esp: {s}0x{x}{s}
        ,
            .{
                "═" ** 11 ++ "╤" ++ "═" ** (tty.width - 12),
                "│\n" ++ "─" ** 11 ++ "┘\n",
                c.green,
                size,
                c.reset,
                c.green,
                size,
                c.reset,
                c.yellow,
                si.fp,
                c.reset,
                c.red,
                esp,
                c.reset,
            },
        );
        if (pc) |addr| tty.printk(", pc: {s}0x{x}{s}", .{ c.blue, addr, c.reset });
        tty.printk("\n\nhex dump:\n", .{});

        memory_dump(si.fp + @sizeOf(usize), esp);
        esp = si.fp + @sizeOf(usize);
        tty.printk("\n", .{});
        if (si.next()) |addr| {
            if (si.fp > @intFromPtr(stack_bottom)) break;
            pc = addr;
        } else break;
    }
    tty.printk("═" ** tty.width ++ "\n", .{});
}

pub fn print_mmap() void {
    if (multiboot.get_tag(multiboot2_h.MULTIBOOT_TAG_TYPE_BASIC_MEMINFO)) |basic_meminfo| {
        tty.printk("mem lower: 0x{x:0>8} Kb\n", .{basic_meminfo.mem_lower});
        tty.printk("mem upper: 0x{x:0>8} Kb\n", .{basic_meminfo.mem_upper});
    }

    if (multiboot.get_tag(multiboot2_h.MULTIBOOT_TAG_TYPE_MMAP)) |t| {
        tty.printk("╔{s:═<18}╤{s:═^18}╤{s:═<18}╗\n", .{
            "",
            " MMAP ",
            "",
        }); // 14
        tty.printk("║ {s: <16} │ {s: <16} │ {s: <16} ║\n", .{
            "base",
            "length",
            "type",
        }); // 14

        var iter = multiboot.mmap_it{ .base = t };
        while (iter.next()) |e| {
            tty.printk("╠{s:═<18}╪{s:═^18}╪{s:═<18}╣\n", .{
                "",
                "",
                "",
            }); // 14
            tty.printk("║ 0x{x:0>14} │ 0x{x:0>14} │ {d: <16} ║\n", .{
                e.base,
                e.length,
                e.type,
            }); // 14
        }
        tty.printk("╚{s:═<18}╧{s:═^18}╧{s:═<18}╝\n", .{
            "",
            "",
            "",
        }); // 14
    }
}

fn get_section_name(offset: usize) ?[]const u8 {
    if (multiboot.get_tag(multiboot2_h.MULTIBOOT_TAG_TYPE_ELF_SECTIONS)) |t| {
        const shstrtab_header = multiboot.get_section_header(t, t.shndx) orelse return null;

        const shstrtab_ptr: [*]u8 = @ptrFromInt(shstrtab_header.sh_addr + 0xc0000000);
        const shstrtab = shstrtab_ptr[0..shstrtab_header.sh_size];

        if (offset > shstrtab.len) return null;

        var i: usize = offset;
        while (i < shstrtab.len and shstrtab[i] != 0) i += 1;

        return shstrtab[offset..i];
    }
    return null;
}

pub fn print_elf() void {
    if (multiboot.get_tag(multiboot2_h.MULTIBOOT_TAG_TYPE_ELF_SECTIONS)) |t| {
        var iter = multiboot.section_hdr_it{ .base = t };
        tty.printk("{s: >17} {s: <3} {s: <8} {s: <8} {s: <8} {s: <8}\n", .{
            "name",
            "flags",
            "virtual",
            "physical",
            "size",
            "type",
        });
        while (iter.next()) |e| {
            var name = get_section_name(e.sh_name) orelse "";
            name = name[0..@min(17, name.len)];
            tty.printk("{s: <17} {x:0>3}   {x:0>8} {x:0>8} {x:0>8} {s}\n", .{
                name,
                @as(u32, @bitCast(e.sh_flags)),
                e.sh_addr,
                e.sh_offset,
                e.sh_size,
                @tagName(e.sh_type)[4..],
            });
        }
    }
}

const multiboot = @import("../multiboot.zig");
const multiboot2_h = @import("../c_headers.zig").multiboot2_h;

pub fn get_section_header_by_name(name: []const u8) ?multiboot.section_entry {
    if (multiboot.get_tag(multiboot2_h.MULTIBOOT_TAG_TYPE_ELF_SECTIONS)) |t| {
        var iter = multiboot.section_hdr_it{ .base = t };
        while (iter.next()) |e| {
            const section_name = get_section_name(e.sh_name) orelse continue;
            if (@import("std").mem.eql(u8, name, section_name)) return e.*;
        }
        while (true) {}
    }
    return null;
}

pub fn show_palette() void {
    for (0..8) |i| {
        tty.printk("\x1b[{d}m" ++ "\xdb" ** 10 ++ "\x1b[0m", .{30 + i});
    }
    for (0..8) |i| {
        tty.printk("\x1b[1m\x1b[{d}m" ++ "\xdb" ** 10 ++ "\x1b[0m", .{30 + i});
    }
}

pub fn fuzz(allocator: std.mem.Allocator, writer: std.io.AnyWriter, nb: usize, max_size: usize, quiet: bool) !void {
    const Fuzzer = @import("../memory/fuzzer.zig").Fuzzer(1000);

    var fuzzer: Fuzzer = Fuzzer.init(allocator, writer, &Fuzzer.converging);
    defer fuzzer.deinit();

    return fuzzer.fuzz(nb, max_size, quiet);
}

const task = @import("../task/task.zig");
const taskSet = @import("../task/task_set.zig");
pub fn pstree(shell: anytype, pid: task.TaskDescriptor.Pid, prefix: []u8, depth: usize) void {
    const descriptor = taskSet.get_task_descriptor(pid) orelse return;
    if (descriptor.childs) |first_child| {
        shell.print("{d:─<5}", .{@as(u32, @intCast(descriptor.pid))});
        if ((depth + 1) * 6 > prefix.len) return;
        var child: ?*task.TaskDescriptor = first_child;
        while (child) |current| : (child = current.next_sibling) {
            if (current == first_child) {
                if (current.next_sibling == null) {
                    shell.print("─", .{});
                } else {
                    shell.print("┬", .{});
                    prefix[depth * 6 + 5] = 0xb3;
                }
            } else if (current.next_sibling == null) {
                prefix[depth * 6 + 5] = ' ';
                shell.print("{s}└", .{prefix[0 .. (depth + 1) * 6 - 1]});
            } else {
                shell.print("{s}├", .{prefix[0 .. (depth + 1) * 6 - 1]});
            }
            pstree(shell, current.pid, prefix, depth + 1);
        }
    } else {
        shell.print("{d}\n", .{descriptor.pid});
    }
}

const SignalId = @import("../task/signal.zig").Id;

pub fn waitpid(shell: anytype, pid: i32) void {
    var status: @import("../task/wait.zig").Status = undefined;
    const ret = @import("../task/wait.zig").wait(
        pid,
        .SELF,
        &status,
        null,
        .{
            .WNOHANG = false,
            .WCONTINUED = false,
            .WUNTRACED = false,
        },
    ) catch |e| {
        shell.print_error("waitpid: wait error: {s}", .{@errorName(e)});
        return;
    };
    if (ret == 0)
        return;
    print_status(shell, ret, status);
}

pub fn print_status(shell: anytype, pid: i32, status: @import("../task/wait.zig").Status) void {
    switch (status.type) {
        .Exited => shell.print("task {d} has exited with code {d}\n", .{ pid, status.value }),
        .Signaled => shell.print(
            "task {d} was terminated by signal {d} ({s})\n",
            .{
                pid,
                status.value,
                @tagName(@as(SignalId, @enumFromInt(status.value))),
            },
        ),
        .Stopped => shell.print(
            "task {d} was stopped by signal {d} ({s})\n",
            .{
                pid,
                status.value,
                @tagName(@as(SignalId, @enumFromInt(status.value))),
            },
        ),
        .Continued => shell.print(
            "task {d} was continued by signal {d} ({s})\n",
            .{
                pid,
                status.value,
                @tagName(@as(SignalId, @enumFromInt(status.value))),
            },
        ),
    }
}
