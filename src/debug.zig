const std = @import("std");
const logger = std.log.scoped(.debug);
const allocator = @import("memory.zig").bigAlloc.allocator();
const utils = @import("shell/utils.zig");

var sections: std.debug.Dwarf.SectionArray = std.debug.Dwarf.null_section_array;
var dwarf_info: ?std.debug.Dwarf = null;

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
    try dumpStackTrace(std.debug.StackIterator.init(@returnAddress(), null));
}

pub fn dumpStackTrace(stack_it: std.debug.StackIterator) !void {
    const tty = @import("tty/tty.zig");
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
