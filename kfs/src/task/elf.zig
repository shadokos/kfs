const std = @import("std");
const paging = @import("../memory/paging.zig");
const regions = @import("../memory/regions.zig");
const RegionSet = @import("../memory/region_set.zig").RegionSet;
const VirtualSpace = @import("../memory/virtual_space.zig").VirtualSpace;

const Ehdr = std.elf.Ehdr; // std.elf.Ehdr -> std.elf.Elf32_Ehdr on i386
const Phdr = std.elf.Phdr; // std.elf.Phdr -> std.elf.Elf32_Phdr on i386

/// Everything a sysv i386 '_start' (and later a dynamic linker) needs to bootstrap a process.
/// 'phdr_vaddr' is the runtime address of the program header table when a PT_LOAD segment maps it,
/// else 0
pub const Image = struct {
    entry: usize,
    phdr_vaddr: usize,
    phentsize: u16,
    phnum: u16,
};

pub const Error = error{
    // malformed or invalid ELF file (inconsistent headers, program table etc)
    InvalidElf,
    // wellformed but can't execute: wrong class/endian/machine/type or dynamic (PT_INTERP), loader only static for now
    UnsupportedElf,
    // ran out of regions / memory while loading the image
    LoadFailed,
};

/// Returns true if the range [offset, offset + len[ is within [0, total[
inline fn in_bounds(offset: usize, len: usize, total: usize) bool {
    // check for overflow
    const end = std.math.add(usize, offset, len) catch return false;
    return end <= total;
}

fn parse_header(data: []const u8) Error!Ehdr {
    if (data.len < @sizeOf(Ehdr)) return Error.InvalidElf;
    const header = std.mem.bytesToValue(Ehdr, data[0..@sizeOf(Ehdr)]);

    if (!std.mem.eql(u8, header.e_ident[0..4], std.elf.MAGIC)) return Error.InvalidElf;
    if (header.e_ident[std.elf.EI_CLASS] != std.elf.ELFCLASS32) return Error.UnsupportedElf;
    if (header.e_ident[std.elf.EI_DATA] != std.elf.ELFDATA2LSB) return Error.UnsupportedElf;
    if (header.e_machine != .@"386") return Error.UnsupportedElf;

    // We only support static executables (ET_DYN/PIE are rejected for now)
    // TODO: remove this check when we implement dynamic linking
    if (header.e_type != .EXEC) return Error.UnsupportedElf;

    // program header table must exist and be within the file
    if (header.e_phoff == 0 or header.e_phnum == 0) return Error.InvalidElf;
    // entries smaller than a Phdr would make PhdrIterator read past the table
    if (header.e_phentsize < @sizeOf(Phdr)) return Error.InvalidElf;
    if (!in_bounds(header.e_phoff, @as(usize, header.e_phnum) * header.e_phentsize, data.len))
        return Error.InvalidElf;

    return header;
}

/// Walks the program header table. Only valid on a header returned by parse_header,
/// which has checked the whole table lies within 'data'.
const PhdrIterator = struct {
    data: []const u8,
    header: Ehdr,
    index: usize = 0,

    fn next(self: *PhdrIterator) ?Phdr {
        if (self.index >= self.header.e_phnum) return null;
        defer self.index += 1;
        const offset = self.header.e_phoff + self.index * @as(usize, self.header.e_phentsize);
        return std.mem.bytesToValue(Phdr, self.data[offset..][0..@sizeOf(Phdr)]);
    }
};

fn check_segment(data: []const u8, phdr: Phdr) Error!void {
    if (phdr.p_filesz > phdr.p_memsz) return Error.InvalidElf; // file size can't be larger than memory size
    if (!in_bounds(phdr.p_offset, phdr.p_filesz, data.len)) return Error.InvalidElf;

    const vm_end = std.math.add(usize, phdr.p_vaddr, phdr.p_memsz) catch return Error.InvalidElf;
    // the segment is wellformed but reaches into the kernel half, so we cannot map it
    if (vm_end > paging.high_half) return Error.InvalidElf;
}

pub fn validate(data: []const u8) Error!void {
    const header = try parse_header(data);

    var it = PhdrIterator{ .data = data, .header = header };
    while (it.next()) |phdr| {
        switch (phdr.p_type) {
            std.elf.PT_LOAD => try check_segment(data, phdr),
            std.elf.PT_INTERP => return Error.UnsupportedElf, // dynamic linking not supported yet
            else => {}, // ignore other segment types
        }
    }
}

fn load_segment(vm: *VirtualSpace, data: []const u8, phdr: Phdr) Error!void {
    try check_segment(data, phdr);

    const vm_start = std.mem.alignBackward(usize, phdr.p_vaddr, paging.page_size);
    const vm_end = std.mem.alignForward(usize, phdr.p_vaddr + phdr.p_memsz, paging.page_size);

    const region = RegionSet.create_region() catch return Error.LoadFailed;
    errdefer RegionSet.destroy_region(region) catch unreachable;
    region.flags = .{ .write = true, .read = true, .may_write = true, .may_read = true };
    regions.VirtuallyContiguousRegion.init(region, .{ .private = true });

    vm.add_region_at(region, vm_start / paging.page_size, (vm_end - vm_start) / paging.page_size, false) catch
        return Error.LoadFailed;

    const dest: [*]u8 = @ptrFromInt(phdr.p_vaddr);
    @memcpy(dest[0..phdr.p_filesz], data[phdr.p_offset..][0..phdr.p_filesz]);

    // since we're not using physical address extension, any readable page is also executable.
    // we only need to handle the write permission here
    if (phdr.p_flags & std.elf.PF_W == 0) {
        region.flags.write = false;
        region.flags.may_write = false;
        region.flush();
    }
}

pub fn load(vm: *VirtualSpace, data: []const u8) Error!Image {
    const header = try parse_header(data);
    const table_size = @as(usize, header.e_phentsize) * header.e_phnum;

    var phdr_vaddr: usize = 0;
    var it = PhdrIterator{ .data = data, .header = header };
    while (it.next()) |phdr| {
        switch (phdr.p_type) {
            std.elf.PT_LOAD => {
                try load_segment(vm, data, phdr);
                if (phdr_vaddr == 0 and
                    header.e_phoff >= phdr.p_offset and
                    in_bounds(header.e_phoff - phdr.p_offset, table_size, phdr.p_filesz))
                    phdr_vaddr = phdr.p_vaddr + (header.e_phoff - phdr.p_offset);
            },
            std.elf.PT_INTERP => return Error.UnsupportedElf, // dynamic linking not supported yet
            else => {}, // ignore other segment types
        }
    }

    return Image{
        .entry = header.e_entry,
        .phdr_vaddr = phdr_vaddr,
        .phentsize = header.e_phentsize,
        .phnum = header.e_phnum,
    };
}
