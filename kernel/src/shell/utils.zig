const std = @import("std");
const tty = @import("../tty/tty.zig");
const StackIterator = std.debug.StackIterator;

const c = @import("colors");

const prompt: *const [2:0]u8 = "»";
extern var stack_bottom: [*]u8;

pub fn ensure_newline(writer: std.io.AnyWriter) void {
    writer.print("{s}\x1b[{d}C\r", .{
        c.invert ++ "%" ++ c.reset, // No newline char: '%' character in reverse
        tty.width - 2, // Move cursor to the end of the line or on the next line if the line is not empty
    }) catch {};
}

pub fn print_error(shell: anytype, comptime msg: []const u8, args: anytype) void {
    ensure_newline(shell.writer);
    shell.writer.print(c.red ++ "Error" ++ c.reset ++ ": " ++ msg ++ "\n", args) catch {};
}

pub fn print_prompt(shell: anytype) void {
    ensure_newline(shell.writer);

    // print the prompt:
    // prompt collor depending on the last command status
    shell.writer.print("{s}{s}" ++ c.reset ++ " ", .{
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

pub fn print_mmap() void {
    if (multiboot.get_tag(multiboot2_h.MULTIBOOT_TAG_TYPE_BASIC_MEMINFO)) |basic_meminfo| {
        tty.printk("mem lower: 0x{x:0>8} Kb\n", .{basic_meminfo.mem_lower});
        tty.printk("mem upper: 0x{x:0>8} Kb\n", .{basic_meminfo.mem_upper});
    }

    if (multiboot.get_tag(multiboot2_h.MULTIBOOT_TAG_TYPE_MMAP)) |t| {
        tty.printk("╔{s:\xcd<18}╤{s:\xcd^18}╤{s:\xcd<18}╗\n", .{
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
            tty.printk("╠{s:\xcd<18}╪{s:\xcd^18}╪{s:\xcd<18}╣\n", .{
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
        tty.printk("╚{s:\xcd<18}╧{s:\xcd^18}╧{s:\xcd<18}╝\n", .{
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

pub fn fuzz(allocator: std.mem.Allocator, writer: *std.io.Writer, nb: usize, max_size: usize, quiet: bool) !void {
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
        shell.print("{d:\xc4<5}", .{@as(u32, @intCast(descriptor.pid))});
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
