const tty = @import("../../tty/tty.zig");
const ft = @import("../../ft/ft.zig");
const StackIterator = ft.debug.StackIterator;
const Shell = @import("shell.zig").Shell;

const c = @import("colors");

const prompt: *const [1:0]u8 = "\xaf";
extern var stack_bottom: [*]u8;

pub fn ensure_newline(writer: ft.io.AnyWriter) void {
    ft.fmt.format(writer, "{s}\x1b[{d}C\r", .{
        c.invert ++ "%" ++ c.reset, // No newline char: '%' character in reverse
        tty.width - 2, // Move cursor to the end of the line or on the next line if the line is not empty
    }) catch {};
}

pub fn print_error(shell: anytype, comptime msg: []const u8, args: anytype) void {
    ensure_newline(shell.writer);
    ft.fmt.format(shell.writer, c.red ++ "Error" ++ c.reset ++ ": " ++ msg ++ "\n", args) catch {};
}

pub fn print_prompt(shell: *const Shell) void {
    ensure_newline(shell.writer);
    ft.fmt.format(shell.writer, "{s}{s}" ++ c.reset ++ " ", .{ // print the prompt:
        if (shell.err) c.red else c.cyan, // prompt collor depending on the last command status
        prompt, // prompt
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

        _ = ft.fmt.bufPrint(&line, "{x:0>8}: ", .{start +| i}) catch {};

        while (ptr +| 1 < start +| i +| 16 and ptr < end) : ({
            ptr +|= 2;
            offset += 5;
            offsetPreview += 2;
        }) {
            const byte1: u8 = @as(*allowzero u8, @ptrFromInt(ptr)).*;
            const byte2: u8 = @as(*allowzero u8, @ptrFromInt(ptr +| 1)).*;

            _ = ft.fmt.bufPrint(line[10 + offset ..], "{x:0>2}{x:0>2} ", .{ byte1, byte2 }) catch {};
            _ = ft.fmt.bufPrint(line[51 + offsetPreview ..], "{s}{s}", .{
                [_]u8{if (ft.ascii.isPrint(byte1)) byte1 else '.'},
                [_]u8{if (ft.ascii.isPrint(byte2)) byte2 else '.'},
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
    tty.printk("   \xDA" ++ "\xC4" ** 12 ++ "\xBF <- {s}0x{x:0>8}{s}\n", .{ c.red, esp, c.reset });
    while (true) {
        var size = si.fp - esp;

        if (pc) |_| size -= @sizeOf(usize);
        if (size > 0)
            tty.printk("{s}\xB3     ...    \xB3 {s}{d}{s} bytes\n{s}", .{
                if (link) "\xB3  " else "   ",                                         c.green, size, c.reset,
                (if (link) "\xB3  " else "   ") ++ "\xC3" ++ "\xC4" ** 12 ++ "\xB4\n",
            });
        old_fp = si.fp;
        esp = si.fp + @sizeOf(usize);
        if (si.next()) |addr| {
            pc = addr;
            tty.printk("{s}\xB3 {s}0x{x:0>8}{s} \xB3 <- {s}0x{x:0>8}{s}\n", .{
                if (link) "\xC0> " else "   ",
                c.yellow,
                si.fp,
                c.reset,
                c.yellow,
                old_fp,
                c.reset,
            });
            link = true;
            if (si.fp > @intFromPtr(stack_bottom)) break;
            tty.printk("   \xC0\xC4\xC2" ++ "\xC4" ** 10 ++ "\xD9\n", .{});
            tty.printk("\xDA" ++ "\xC4" ** 4 ++ "\xD9\n", .{});
            tty.printk("\xB3  \xDA" ++ "\xC4" ** 12 ++ "\xBF\n", .{});
            tty.printk("\xB3  \xB3 {s}0x{x:0>8}{s} \xB3 <- {s}0x{x:0>8}{s}\n", .{
                c.blue, addr, c.reset,
                c.red,  esp,  c.reset,
            });
            tty.printk("\xB3  \xC3" ++ "\xC4" ** 12 ++ "\xB4\n", .{});
        } else {
            tty.printk("{s}\xB3 {s}0x{x:0>8}{s} \xB3 <- {s}0x{x:0>8}{s}\n", .{
                if (link) "\xC0> " else "   ",
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
    tty.printk("   \xC0" ++ "\xC4" ** 12 ++ "\xD9\n", .{});
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
                "\xCD" ** 11 ++ "\xD1" ++ "\xCD" ** (tty.width - 12),
                "\xB3\n" ++ "\xC4" ** 11 ++ "\xD9\n",
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
    tty.printk("\xCD" ** tty.width ++ "\n", .{});
}

pub fn print_mmap() void {
    const multiboot = @import("../../multiboot.zig");
    const multiboot2_h = @import("../../c_headers.zig").multiboot2_h;

    if (multiboot.get_tag(multiboot2_h.MULTIBOOT_TAG_TYPE_BASIC_MEMINFO)) |basic_meminfo| {
        tty.printk("mem lower: 0x{x:0>8} Kb\n", .{basic_meminfo.mem_lower});
        tty.printk("mem upper: 0x{x:0>8} Kb\n", .{basic_meminfo.mem_upper});
    }

    if (multiboot.get_tag(multiboot2_h.MULTIBOOT_TAG_TYPE_MMAP)) |t| {
        tty.printk("\xC9{s:\xCD<18}\xD1{s:\xCD^18}\xD1{s:\xCD<18}\xBB\n", .{
            "",
            " MMAP ",
            "",
        }); // 14
        tty.printk("\xBA {s: <16} \xB3 {s: <16} \xB3 {s: <16} \xBA\n", .{
            "base",
            "length",
            "type",
        }); // 14

        var iter = multiboot.mmap_it{ .base = t };
        while (iter.next()) |e| {
            tty.printk("\xCC{s:\xCD<18}\xD8{s:\xCD^18}\xD8{s:\xCD<18}\xB9\n", .{
                "",
                "",
                "",
            }); // 14
            tty.printk("\xBA 0x{x:0>14} \xB3 0x{x:0>14} \xB3 {d: <16} \xBA\n", .{
                e.base,
                e.length,
                e.type,
            }); // 14
        }
        tty.printk("\xC8{s:\xCD<18}\xCF{s:\xCD^18}\xCF{s:\xCD<18}\xBC\n", .{
            "",
            "",
            "",
        }); // 14
    }
}

pub fn print_elf() void {
    const multiboot = @import("../../multiboot.zig");
    const multiboot2_h = @import("../../c_headers.zig").multiboot2_h;
    if (multiboot.get_tag(multiboot2_h.MULTIBOOT_TAG_TYPE_ELF_SECTIONS)) |t| {
        var iter = multiboot.section_hdr_it{ .base = t };
        tty.printk("{s: <32} {s: <8} {s: <8} {s: <8} {s: <8}\n", .{
            "flags",
            "virtual",
            "physical",
            "size",
            "type",
        });
        while (iter.next()) |e| {
            tty.printk("{b:0>32} {x:0>8} {x:0>8} {x:0>8} {}\n", .{
                @as(u32, @bitCast(e.sh_flags)),
                e.sh_addr,
                e.sh_offset,
                e.sh_size,
                @intFromEnum(e.sh_type),
            });
        }
    }
}

pub fn show_palette() void {
    for (0..8) |i| {
        tty.printk("\x1b[{d}m" ++ "\xdb" ** 10 ++ "\x1b[0m", .{30 + i});
    }
    for (0..8) |i| {
        tty.printk("\x1b[2m\x1b[{d}m" ++ "\xdb" ** 10 ++ "\x1b[0m", .{30 + i});
    }
}

pub fn fuzz(allocator: ft.mem.Allocator, nb: usize, max_size: usize) !void {
    const Fuzzer = @import("../../memory/fuzzer.zig").Fuzzer(1000);

    var fuzzer: Fuzzer = Fuzzer.init(allocator, &Fuzzer.converging);
    defer fuzzer.deinit();

    return fuzzer.fuzz(nb, max_size);
}
