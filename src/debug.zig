const std = @import("std");
const c = @import("colors");
const logger = std.log.scoped(.debug);
const allocator = @import("memory.zig").bigAlloc.allocator();
const utils = @import("shell/utils.zig");
const tty = @import("tty/tty.zig");

var sections: std.debug.Dwarf.SectionArray = std.debug.Dwarf.null_section_array;
pub var dwarf_info: ?std.debug.Dwarf = null;

pub fn init() void {
    const eh_frame_header = utils.get_section_header_by_name(".eh_frame") orelse {
        logger.warn("Failed to get eh_frame header", .{});
        return;
    };
    const debug_info_header = utils.get_section_header_by_name(".debug_info") orelse {
        logger.warn("Failed to get debug_info header", .{});
        return;
    };
    const debug_abbrev_header = utils.get_section_header_by_name(".debug_abbrev") orelse {
        logger.warn("Failed to get debug_abbrev header", .{});
        return;
    };
    const debug_str_header = utils.get_section_header_by_name(".debug_str") orelse {
        logger.warn("Failed to get debug_str header", .{});
        return;
    };
    const debug_line_header = utils.get_section_header_by_name(".debug_line") orelse {
        logger.warn("Failed to get debug_line header", .{});
        return;
    };
    const debug_ranges_header = utils.get_section_header_by_name(".debug_ranges") orelse {
        logger.warn("Failed to get debug_ranges header", .{});
        return;
    };

    sections[@as(u8, @intFromEnum(std.debug.Dwarf.Section.Id.eh_frame))] = std.debug.Dwarf.Section{
        .data = @as([*]u8, @ptrFromInt(eh_frame_header.sh_addr))[0..eh_frame_header.sh_size],
        .owned = false,
    };
    sections[@as(u8, @intFromEnum(std.debug.Dwarf.Section.Id.debug_info))] = std.debug.Dwarf.Section{
        .data = @as([*]u8, @ptrFromInt(debug_info_header.sh_addr + 0xc000_0000))[0..debug_info_header.sh_size],
        .owned = false,
    };
    sections[@as(u8, @intFromEnum(std.debug.Dwarf.Section.Id.debug_abbrev))] = std.debug.Dwarf.Section{
        .data = @as([*]u8, @ptrFromInt(debug_abbrev_header.sh_addr + 0xc000_0000))[0..debug_abbrev_header.sh_size],
        .owned = false,
    };
    sections[@as(u8, @intFromEnum(std.debug.Dwarf.Section.Id.debug_str))] = std.debug.Dwarf.Section{
        .data = @as([*]u8, @ptrFromInt(debug_str_header.sh_addr + 0xc000_0000))[0..debug_str_header.sh_size],
        .owned = false,
    };
    sections[@as(u8, @intFromEnum(std.debug.Dwarf.Section.Id.debug_line))] = std.debug.Dwarf.Section{
        .data = @as([*]u8, @ptrFromInt(debug_line_header.sh_addr + 0xc000_0000))[0..debug_line_header.sh_size],
        .owned = false,
    };
    sections[@as(u8, @intFromEnum(std.debug.Dwarf.Section.Id.debug_ranges))] = std.debug.Dwarf.Section{
        .data = @as([*]u8, @ptrFromInt(debug_ranges_header.sh_addr + 0xc000_0000))[0..debug_ranges_header.sh_size],
        .owned = false,
    };

    dwarf_info = std.debug.Dwarf{
        .endian = .little,
        .is_macho = false,
        .sections = sections,
    };

    dwarf_info.?.open(allocator) catch |err| {
        logger.warn("Unable to retrieve dwarf infos: {s}", .{@errorName(err)});
        dwarf_info = null;
        return;
    };

    logger.info("DWARF info initialized", .{});
}

pub fn dumpCurrentStackTrace() !void {
    try dumpStackTrace(std.debug.StackIterator.init(@returnAddress(), @frameAddress()));
}

pub fn dumpStackTrace(stack_it: std.debug.StackIterator) !void {
    var it: std.debug.StackIterator = stack_it;

    if (dwarf_info == null)
        return error.DwarfNotInitialized;

    tty.printk("Backtrace:\n", .{});
    while (it.next()) |_addr| {
        const sym = dwarf_info.?.getSymbol(allocator, _addr) catch |err| {
            tty.printk("Failed to get symbol: {s}\n", .{@errorName(err)});
            continue;
        };
        if (sym.source_location) |loc| {
            tty.printk("{s}:{d}:{d} \x1b[34m{s}\x1b[0m\n", .{ loc.file_name, loc.line, loc.column, sym.name });
        } else {
            tty.printk("???:?:?\n", .{});
        }
    }
    tty.printk("\n", .{});
}

pub fn dumpCurrentStackTraceVerbose() !void {
    try dumpStackTraceVerbose(std.debug.StackIterator.init(@returnAddress(), @frameAddress()));
}

pub fn dumpStackTraceVerbose(stack_it: std.debug.StackIterator) !void {
    var it: std.debug.StackIterator = stack_it;
    var old_fp: usize = it.fp;

    while (it.next()) |_addr| {
        const sym = dwarf_info.?.getSymbol(allocator, _addr) catch |err| {
            tty.printk("Failed to get symbol: {s}\n", .{@errorName(err)});
            continue;
        };

        tty.printk("═" ** tty.width, .{});
        tty.printk("{s}{s: ^80}{s}\n", .{ c.cyan, sym.name, c.reset });

        tty.printk("frame:\n- ebp: 0x{x}\n- esp: 0x{x}\n- ret: 0x{x}\n\n", .{ it.fp, old_fp, _addr });

        if (sym.source_location) |loc| {
            tty.printk("file: {s}:{d}:{d}\n\n", .{ loc.file_name, loc.line, loc.column });
        } else {
            tty.printk("file: ???:?:?\n\n", .{});
        }

        const size = it.fp - old_fp;
        tty.printk("memory dump ({d} bytes):\n", .{size});
        memory_dump(old_fp, it.fp, null);
        tty.printk("\n", .{});

        old_fp = it.fp;
    }
}

const DumpMode = enum {
    Address,
    Offset,
};

pub fn memory_dump(start_address: usize, end_address: usize, offset: ?usize) void {
    const start: usize = @min(start_address, end_address);
    const end: usize = @max(start_address, end_address);

    var i: usize = 0;
    var last_chunk: [16]u8 = [_]u8{0} ** 16;
    var has_shown_asterisk = false;

    while (start +| i <= end) : (i +|= 16) {
        const ptr: usize = start +| i;
        var current_chunk: [16]u8 = [_]u8{0} ** 16;

        // Read the current 16-byte chunk
        var j: usize = 0;
        while (j < 16 and ptr +| j < end) : (j += 1) {
            current_chunk[j] = @as(*allowzero u8, @ptrFromInt(ptr +| j)).*;
        }

        // Check if this chunk is identical to the last one
        if (i > 0 and std.mem.eql(u8, &current_chunk, &last_chunk)) {
            if (!has_shown_asterisk) {
                tty.printk("*\n", .{});
                has_shown_asterisk = true;
            }
        } else {
            has_shown_asterisk = false;

            // Format and print the line
            var _offset: usize = 0;
            var offsetPreview: usize = 0;
            var line: [69]u8 = [_]u8{' '} ** 69;

            _ = std.fmt.bufPrint(&line, "{x:0>8}: ", .{ptr - (offset orelse 0)}) catch {};

            if (ptr < end)
                _ = std.fmt.bufPrint(line[50..], "\xba{c: >16}\xba", .{' '}) catch {};

            var byte_ptr = ptr;
            while (byte_ptr +| 1 < start +| i +| 16 and byte_ptr < end) : ({
                byte_ptr +|= 2;
                _offset += 5;
                offsetPreview += 2;
            }) {
                const byte1: u8 = @as(*allowzero u8, @ptrFromInt(byte_ptr)).*;
                const byte2: u8 = @as(*allowzero u8, @ptrFromInt(byte_ptr +| 1)).*;

                _ = std.fmt.bufPrint(line[10 + _offset ..], "{x:0>2}{x:0>2} ", .{ byte1, byte2 }) catch {};
                _ = std.fmt.bufPrint(line[51 + offsetPreview ..], "{s}{s}", .{
                    [_]u8{if (std.ascii.isPrint(byte1)) byte1 else '.'},
                    [_]u8{if (std.ascii.isPrint(byte2)) byte2 else '.'},
                }) catch {};
            }

            tty.printk("{s}\n", .{line});
        }

        last_chunk = current_chunk;
    }
}
