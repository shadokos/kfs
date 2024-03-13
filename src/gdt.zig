const logger = @import("ft/ft.zig").log.scoped(.gdt);

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
    privilege: u2 = 0,
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

const GDT_SIZE = 7;

export const GDT: [GDT_SIZE]u64 = .{
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
            .privilege = 0,
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
            .privilege = 0,
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
            .privilege = 0,
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
            .privilege = 3,
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
            .privilege = 3,
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
            .privilege = 3,
            .readable_writable = true,
        }),
    }),
};

const GDTR_type = packed struct(u48) {
    size: u16,
    base: u32,
};

export var GDTR: [3]u16 = undefined;

pub fn init() void {
    logger.debug("Initializing gdt...", .{});
    GDTR = @bitCast(GDTR_type{
        .size = GDT_SIZE * @sizeOf(@typeInfo(@TypeOf(GDT)).Array.child),
        .base = @intFromPtr(&GDT),
    });
    asm volatile (
    // disable interrupts
        \\ cli
        // load gdt
        \\ lgdt (GDTR)
        // load segment registers
        \\ jmp $0b00001000, $.reload_CS
        \\ .reload_CS:
        \\ movw $0b00010000, %ax
        \\ movw %ax, %ds
        \\ movw %ax, %es
        \\ movw %ax, %fs
        \\ movw %ax, %gs
        \\ movw $0b00011000, %ax
        \\ movw %ax, %ss
    );
    logger.info("Gdt initialized", .{});
}
