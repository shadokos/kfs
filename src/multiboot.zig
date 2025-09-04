const std = @import("std");
const multiboot2_h = @import("c_headers.zig").multiboot2_h;
const boot = @import("boot.zig");
const paging = @import("memory/paging.zig");
const tty = @import("tty/tty.zig");

fn mbi_requestN(comptime types: []const u32) type {
    return extern struct {
        type: u16 = 1,
        flags: u16 = 0,
        size: u32 = @sizeOf(@This()),
        mbis: [types.len]u32 = types[0..].*,
    };
}

fn get_header_type(comptime types: []const u32) type {
    return extern struct {
        header: extern struct {
            magic: u32 = multiboot2_h.MULTIBOOT2_HEADER_MAGIC,
            architecture: u32 = multiboot2_h.MULTIBOOT_ARCHITECTURE_I386,
            header_length: u32 = @sizeOf(@This()),
            checksum: u32 = 0,
        } = .{},
        info_req: mbi_requestN(types) align(8) = .{},
        tag_end: multiboot2_h.multiboot_header_tag align(8) = .{ .type = 0, .flags = 0, .size = 8 },
    };
}

pub const header_type = get_header_type(
    ([_]u32{
        multiboot2_h.MULTIBOOT_TAG_TYPE_BASIC_MEMINFO,
        multiboot2_h.MULTIBOOT_TAG_TYPE_MMAP,
        multiboot2_h.MULTIBOOT_TAG_TYPE_ACPI_OLD,
        multiboot2_h.MULTIBOOT_TAG_TYPE_ACPI_NEW,
        multiboot2_h.MULTIBOOT_TAG_TYPE_ELF_SECTIONS,
    })[0..],
);

pub fn get_header() header_type {
    var ret: header_type = .{};

    ret.header.checksum = @bitCast(-(@as(i32, @bitCast(ret.header.magic)) +
        @as(i32, @bitCast(ret.header.architecture)) +
        @as(i32, @bitCast(ret.header.header_length))));

    return ret;
}

pub const section_entry = packed struct {
    sh_name: u32,
    sh_type: ShType,
    sh_flags: ShFlags,
    sh_addr: u32,
    sh_offset: u32,
    sh_size: u32,
    sh_link: u32,
    sh_info: u32,
    sh_addralign: u32,
    sh_entsize: u32,

    const ShType = enum(u32) {
        SHT_NULL = 0x0,
        SHT_PROGBITS = 0x1,
        SHT_SYMTAB = 0x2,
        SHT_STRTAB = 0x3,
        SHT_RELA = 0x4,
        SHT_HASH = 0x5,
        SHT_DYNAMIC = 0x6,
        SHT_NOTE = 0x7,
        SHT_NOBITS = 0x8,
        SHT_REL = 0x9,
        SHT_SHLIB = 0x0A,
        SHT_DYNSYM = 0x0B,
        SHT_INIT_ARRAY = 0x0E,
        SHT_FINI_ARRAY = 0x0F,
        SHT_PREINIT_ARRAY = 0x10,
        SHT_GROUP = 0x11,
        SHT_SYMTAB_SHNDX = 0x12,
        SHT_NUM = 0x13,
        SHT_LOOS = 0x60000000,
    };

    const ShFlags = packed struct(u32) {
        SHF_WRITE: bool,
        SHF_ALLOC: bool,
        SHF_EXECINSTR: bool,
        SHF_MERGE: bool,
        SHF_STRINGS: bool,
        SHF_INFO_LINK: bool,
        SHF_LINK_ORDER: bool,
        SHF_OS_NONCONFORMING: bool,
        SHF_GROUP: bool,
        SHF_TLS: bool,
        padding: u22,
        // SHF_MASKOS : bool,
        // SHF_MASKPROC : bool,
        // SHF_MASKPROC : bool,
        // SHF_EXCLUDE : bool,
    };
};

pub const mmap_entry = extern struct { base: u64, length: u64, type: u32, reserved: u32 };

pub const mmap_it = extern struct {
    base: *tag_type,
    index: usize = 0,

    const tag_type = get_tag_type(multiboot2_h.MULTIBOOT_TAG_TYPE_MMAP);
    pub fn next(self: *@This()) ?*mmap_entry {
        const ret: *mmap_entry = @ptrFromInt(@intFromPtr(&self.base.first_entry) + self.base.entry_size * self.index);
        if (@intFromPtr(ret) >= @intFromPtr(self.base) + self.base.size)
            return null;
        self.index += 1;
        return ret;
    }
};

pub const section_hdr_it = extern struct {
    base: *tag_type,
    index: usize = 0,

    const tag_type = get_tag_type(multiboot2_h.MULTIBOOT_TAG_TYPE_ELF_SECTIONS);
    pub fn next(self: *@This()) ?*section_entry {
        const ret: *section_entry = @ptrFromInt(@intFromPtr(self.base) + @sizeOf(tag_type) +
            self.base.entsize * self.index);
        if (self.base.entsize == 0 or @intFromPtr(ret) >= @intFromPtr(self.base) + self.base.size)
            return null;
        self.index += 1;
        return ret;
    }
};

fn get_tag_type(comptime n: comptime_int) type {
    const array: [multiboot2_h.MULTIBOOT_TAG_TYPE_LOAD_BASE_ADDR + 1]type = .{
        extern struct { // MULTIBOOT_TAG_TYPE_END
        },
        extern struct { // MULTIBOOT_TAG_TYPE_CMDLINE
            first_char: u8,
        },
        extern struct { // MULTIBOOT_TAG_TYPE_BOOT_LOADER_NAME
            first_char: u8,
        },
        extern struct { // MULTIBOOT_TAG_TYPE_MODULE
            mod_start: u32,
            mod_end: u32,
            first_char: u8,
        },
        extern struct { // MULTIBOOT_TAG_TYPE_BASIC_MEMINFO
            mem_lower: u32,
            mem_upper: u32,
        },
        extern struct { // MULTIBOOT_TAG_TYPE_BOOTDEV
            biosdev: u32,
            partition: u32,
            sub_partition: u32,
        },
        extern struct { // MULTIBOOT_TAG_TYPE_MMAP
            entry_size: u32,
            entry_version: u32,
            first_entry: mmap_entry,
        },
        extern struct { // MULTIBOOT_TAG_TYPE_VBE
            vbe_mode: u16,
            vbe_interface_seg: u16,
            vbe_interface_off: u16,
            vbe_interface_len: u16,
            vbe_control_info: [512]u8,
            vbe_mode_info: [256]u8,
        },
        extern struct { // MULTIBOOT_TAG_TYPE_FRAMEBUFFER
            framebuffer_addr: u64,
            framebuffer_pitch: u32,
            framebuffer_width: u32,
            framebuffer_height: u32,
            framebuffer_bpp: u8,
            framebuffer_type: u8,
            reserved: u8,
            first_color_info: u8,
        },
        extern struct { // MULTIBOOT_TAG_TYPE_ELF_SECTIONS
            num: u32,
            entsize: u32,
            shndx: u32,
        },
        extern struct { // MULTIBOOT_TAG_TYPE_APM
            version: u16,
            cseg: u16,
            offset: u32,
            cseg_16: u16,
            dseg: u16,
            flags: u16,
            cseg_len: u16,
            cseg_16_len: u16,
            dseg_len: u16,
        },
        extern struct { // MULTIBOOT_TAG_TYPE_EFI32
            pointer: u32,
        },
        extern struct { // MULTIBOOT_TAG_TYPE_EFI64
            pointer: u64,
        },
        extern struct { // MULTIBOOT_TAG_TYPE_SMBIOS
            major: u8,
            minor: u8,
            reserved: [6]u8,
            // SMBIOS tables
        },
        extern struct { // MULTIBOOT_TAG_TYPE_ACPI_OLD
            rsdp: @import("drivers/acpi/acpi.zig").RSDP,
        },
        extern struct { // MULTIBOOT_TAG_TYPE_ACPI_NEW
            rsdp: @import("drivers/acpi/acpi.zig").RSDP,
        },
        extern struct { // MULTIBOOT_TAG_TYPE_NETWORK
            // DHCP ACK
        },
        extern struct { // MULTIBOOT_TAG_TYPE_EFI_MMAP
            descriptor_size: u32,
            descriptor_version: u32,
            // EFI memory map
        },
        extern struct { // MULTIBOOT_TAG_TYPE_EFI_BS
        },
        extern struct { // MULTIBOOT_TAG_TYPE_EFI32_IH
            pointer: u32,
        },
        extern struct { // MULTIBOOT_TAG_TYPE_EFI64_IH
            pointer: u64,
        },
        extern struct { // MULTIBOOT_TAG_TYPE_LOAD_BASE_ADDR
            load_base_addr: u32,
        },
    };
    const ret = struct {
        type: u32,
        size: u32,
    };
    var tmp = @typeInfo(ret);
    tmp.@"struct".fields = @typeInfo(ret).@"struct".fields ++ @typeInfo(array[n]).@"struct".fields;
    return @Type(tmp);
}

const tag_header = extern struct {
    type: u32,
    size: u32,
};

pub const info_header = extern struct {
    total_size: u32,
    reserved: u32,
};

pub fn get_tag(comptime t: usize) ?*get_tag_type(t) {
    var tag: *align(1) tag_header = @ptrFromInt(@intFromPtr(boot.multiboot_info) + @sizeOf(info_header));
    while (tag.type != multiboot2_h.MULTIBOOT_TAG_TYPE_END) {
        if (tag.type == t) {
            return @ptrCast(@alignCast(tag));
        }
        tag = @ptrFromInt(@intFromPtr(tag) + tag.size);
        tag = @ptrFromInt(std.mem.alignForward(usize, @intFromPtr(tag), multiboot2_h.MULTIBOOT_TAG_ALIGN));
    }
    return null;
}

pub fn list_tags() void {
    var tag: *align(1) tag_header = @ptrFromInt(@intFromPtr(boot.multiboot_info) + @sizeOf(info_header));

    while (tag.type != multiboot2_h.MULTIBOOT_TAG_TYPE_END) {
        tty.printk("tag: type {d} size {d}\n", .{ tag.type, tag.size });
        tag = @ptrFromInt(@intFromPtr(tag) + tag.size);
        tag = @ptrFromInt(std.mem.alignForward(usize, @intFromPtr(tag), multiboot2_h.MULTIBOOT_TAG_ALIGN));
    }
}

pub fn map(ptr: paging.PhysicalPtr) *info_header {
    const memory = @import("memory.zig");
    const header: *info_header = @ptrCast(@alignCast(memory.kernel_virtual_space.map_object_anywhere(
        ptr,
        @sizeOf(info_header),
        .KernelSpace,
    ) catch @panic("can't map multiboot_info")));
    defer memory.kernel_virtual_space.unmap_object(@ptrCast(header), @sizeOf(info_header)) catch unreachable;
    return @ptrCast(@alignCast(memory.kernel_virtual_space.map_object_anywhere(
        ptr,
        header.total_size,
        .KernelSpace,
    ) catch @panic("can't map multiboot_info")));
}
