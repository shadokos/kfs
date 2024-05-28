const logger = @import("ft/ft.zig").log.scoped(.gdt);
const cpu = @import("cpu.zig");

const flag_type = packed struct(u4) {
    _reserved: bool = false,
    long_mode: bool = false,
    size: bool = false,
    granularity: bool = false,
};

const access_byte_type = packed struct(u8) {
    Accessed: bool = false,
    readable_writable: bool = false,
    direction: bool = false,
    executable: bool = false,
    type: bool = false,
    privilege: cpu.PrivilegeLevel = cpu.PrivilegeLevel.Supervisor,
    present: bool = false,
};

const gdt_entry = struct {
    limit: u20,
    base: u32,
    flags: u4,
    access_byte: u8,
};

fn encode_gdt(entry: gdt_entry) u64 {
    return (((@as(u64, entry.base) >> 24) << 56) |
        (@as(u64, entry.flags) << 52) |
        ((@as(u64, entry.limit) >> 16) << 48) |
        (@as(u64, entry.access_byte) << 40) |
        ((@as(u64, entry.base) & 0xffffff) << 16) |
        (@as(u64, entry.limit) & 0xffff));
}

var GDT = [_]u64{
    0,
    encode_gdt(.{ // kernel code
        .base = 0,
        .limit = 0x000FFFFF,
        .flags = @bitCast(flag_type{
            .long_mode = false,
            .size = true,
            .granularity = true,
        }),
        .access_byte = @bitCast(access_byte_type{
            .type = true,
            .present = true,
            .privilege = cpu.PrivilegeLevel.Supervisor,
            .executable = true,
            .readable_writable = true,
        }),
    }),
    encode_gdt(.{ // kernel data
        .base = 0,
        .limit = 0x000FFFFF,
        .flags = @bitCast(flag_type{
            .long_mode = false,
            .size = true,
            .granularity = true,
        }),
        .access_byte = @bitCast(access_byte_type{
            .type = true,
            .present = true,
            .privilege = cpu.PrivilegeLevel.Supervisor,
            .readable_writable = true,
        }),
    }),
    encode_gdt(.{ // kernel stack
        .base = 0,
        .limit = 0x000FFFFF,
        .flags = @bitCast(flag_type{
            .long_mode = false,
            .size = true,
            .granularity = true,
        }),
        .access_byte = @bitCast(access_byte_type{
            .type = true,
            .present = true,
            .privilege = cpu.PrivilegeLevel.Supervisor,
            .readable_writable = true,
        }),
    }),
    encode_gdt(.{ // protected code
        .base = 0,
        .limit = 0x000FFFFF,
        .flags = @bitCast(flag_type{
            .long_mode = false,
            .size = true,
            .granularity = true,
        }),
        .access_byte = @bitCast(access_byte_type{
            .type = true,
            .present = true,
            .privilege = cpu.PrivilegeLevel.User,
            .executable = true,
            .readable_writable = true,
        }),
    }),
    encode_gdt(.{ // protected data
        .base = 0,
        .limit = 0x000FFFFF,
        .flags = @bitCast(flag_type{
            .long_mode = false,
            .size = true,
            .granularity = true,
        }),
        .access_byte = @bitCast(access_byte_type{
            .type = true,
            .present = true,
            .privilege = cpu.PrivilegeLevel.User,
            .readable_writable = true,
        }),
    }),
    encode_gdt(.{ // protected stack
        .base = 0,
        .limit = 0x000FFFFF,
        .flags = @bitCast(flag_type{
            .long_mode = false,
            .size = true,
            .granularity = true,
        }),
        .access_byte = @bitCast(access_byte_type{
            .type = true,
            .present = true,
            .privilege = cpu.PrivilegeLevel.User,
            .readable_writable = true,
        }),
    }),
    0, // Tss
};

pub const GDTR = packed struct(u48) {
    size: u16,
    base: u32,
};

const TableType = enum(u1) {
    GDT = 0,
    LDT = 1,
};

pub fn get_selector(selector: u12, table: TableType, privilege: cpu.PrivilegeLevel) u16 {
    return (@as(u16, selector) << 3) | (@as(u16, @intFromEnum(table)) << 2) | @as(u16, @intFromEnum(privilege));
}

var gdtr: GDTR = undefined;

pub fn init() void {
    logger.debug("Initializing gdt...", .{});
    gdtr = .{
        .size = GDT.len * @sizeOf(@typeInfo(@TypeOf(GDT)).Array.child) - 1,
        .base = @intFromPtr(&GDT),
    };

    // Setting up TSS entry
    GDT[7] = encode_gdt(.{ // Tss
        .base = @intFromPtr(&tss),
        .limit = @sizeOf(@TypeOf(tss)) - 1,
        .access_byte = @bitCast(access_byte_type{
            .present = true,
            .executable = true,
            .Accessed = true,
        }),
        .flags = @bitCast(flag_type{ .size = true }),
    });

    // Initialize TSS
    tss.ss0 = comptime get_selector(3, .GDT, cpu.PrivilegeLevel.Supervisor);
    tss.cs = comptime get_selector(4, .GDT, cpu.PrivilegeLevel.User);
    tss.ss = comptime get_selector(5, .GDT, cpu.PrivilegeLevel.User);

    cpu.load_gdt(&gdtr);
    cpu.load_segments(
        comptime get_selector(1, .GDT, cpu.PrivilegeLevel.Supervisor),
        comptime get_selector(2, .GDT, cpu.PrivilegeLevel.Supervisor),
        comptime get_selector(3, .GDT, cpu.PrivilegeLevel.Supervisor),
    );

    cpu.load_tss(comptime get_selector(7, .GDT, cpu.PrivilegeLevel.Supervisor));

    logger.info("Gdt initialized", .{});
}

pub const Tss = extern struct {
    link: u16 = 0,
    esp0: u32 = 0,
    ss0: u16 = 0,
    esp1: u32 = 0,
    ss1: u16 = 0,
    esp2: u32 = 0,
    ss2: u16 = 0,
    cr3: u32 = 0,
    eip: u32 = 0,
    eflags: u32 = 0,
    eax: u32 = 0,
    ecx: u32 = 0,
    edx: u32 = 0,
    ebx: u32 = 0,
    esp: u32 = 0,
    ebp: u32 = 0,
    esi: u32 = 0,
    edi: u32 = 0,
    es: u32 = 0,
    cs: u32 = 0,
    ss: u32 = 0,
    ds: u32 = 0,
    fs: u32 = 0,
    gs: u32 = 0,
    ldtr: u32 = 0,
    trap: u16 = 0,
    iopb: u16 = @sizeOf(Tss),
};

pub var tss: Tss align(4096) = .{};
