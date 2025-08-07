const logger = @import("std").log.scoped(.gdt);
const cpu = @import("cpu.zig");
const Monostate = @import("misc/monostate.zig").Monostate;

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
    0, // TSS entry
};

pub const GDTR = packed struct(u48) {
    size: u16,
    base: u32,
};

var gdtr: GDTR = undefined;

pub fn flush() void {
    cpu.load_gdt(&gdtr);
}

pub fn init() void {
    logger.debug("Initializing gdt...", .{});
    gdtr = .{
        .size = GDT.len * @sizeOf(@typeInfo(@TypeOf(GDT)).array.child) - 1,
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
    tss.ss0 = .{ .index = 3, .table = .GDT, .privilege = cpu.PrivilegeLevel.Supervisor };
    tss.cs = .{ .index = 4, .table = .GDT, .privilege = cpu.PrivilegeLevel.User };
    tss.ss = .{ .index = 5, .table = .GDT, .privilege = cpu.PrivilegeLevel.User };

    flush();
    cpu.load_segments(
        .{ .index = 1, .table = .GDT, .privilege = cpu.PrivilegeLevel.Supervisor },
        .{ .index = 2, .table = .GDT, .privilege = cpu.PrivilegeLevel.Supervisor },
        .{ .index = 3, .table = .GDT, .privilege = cpu.PrivilegeLevel.Supervisor },
    );

    cpu.load_tss(.{ .index = 7, .table = .GDT, .privilege = cpu.PrivilegeLevel.Supervisor });

    logger.info("Gdt initialized", .{});
}

pub const Tss = extern struct {
    link: cpu.Selector = .{},
    _unused1: Monostate(u16, 0) = .{},
    esp0: u32 = 0,
    ss0: cpu.Selector = .{},
    _unused2: Monostate(u16, 0) = .{},
    esp1: u32 = 0,
    ss1: cpu.Selector = .{},
    _unused3: Monostate(u16, 0) = .{},
    esp2: u32 = 0,
    ss2: cpu.Selector = .{},
    _unused4: Monostate(u16, 0) = .{},
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
    es: cpu.Selector = .{},
    _unused5: Monostate(u16, 0) = .{},
    cs: cpu.Selector = .{},
    _unused6: Monostate(u16, 0) = .{},
    ss: cpu.Selector = .{},
    _unused7: Monostate(u16, 0) = .{},
    ds: cpu.Selector = .{},
    _unused8: Monostate(u16, 0) = .{},
    fs: cpu.Selector = .{},
    _unused9: Monostate(u16, 0) = .{},
    gs: cpu.Selector = .{},
    _unused10: Monostate(u16, 0) = .{},
    ldtr: u32 = 0,
    trap: u16 = 0,
    iopb: u16 = @sizeOf(Tss),
};

pub var tss: Tss align(4096) = .{};
