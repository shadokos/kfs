const logger = @import("ft/ft.zig").log.scoped(.interrupts);

pub const Handler = extern union {
    ptr: usize,
    err: *const fn (u32) callconv(.Interrupt) void,
    noerr: *const fn () callconv(.Interrupt) void,
};

const IDTR = packed struct {
    size: u16 = 0x7ff,
    offset: u64 = undefined,
};

var idtr: IDTR = .{};

const GateType = enum(u5) {
    Task = 0b00101,
    Interrupt = 0b01110,
    Trap = 0b01111,
};

pub const InterruptDescriptor = packed struct {
    offset_1: u16 = undefined,
    selector: u16 = undefined,
    unused: u8 = 0,
    gate: GateType = undefined,
    privilege: u2 = undefined,
    present: bool = false,
    offset_2: u16 = undefined,

    const Self = @This();

    pub fn init(offset: Handler, gate: GateType, privilege: u2, selector: u16) Self {
        var interrupt_descriptor = Self{
            .gate = gate,
            .privilege = privilege,
            .selector = selector,
            .present = true,
        };
        interrupt_descriptor.set_offset(offset);
        return interrupt_descriptor;
    }

    pub fn deinit(self: *Self) void {
        self.present = false;
    }

    pub fn set_offset(self: *Self, offset: Handler) void {
        self.offset_1 = @truncate(offset.ptr);
        self.offset_2 = @truncate(offset.ptr >> 16);
    }
};

var idt: [256]InterruptDescriptor = [_]InterruptDescriptor{.{}} ** 256;

fn zero_div() callconv(.Interrupt) void {
    @panic("ZERO DIV :(");
}

fn handler_err(code: u32) callconv(.Interrupt) void {
    logger.err("handler_err: {d}", .{code});
}

fn handler_noerr() callconv(.Interrupt) void {
    logger.err("handler_noerr", .{});
}

pub fn init() void {
    logger.debug("Initializing idt...", .{});
    idt[0] = InterruptDescriptor.init(.{ .noerr = &zero_div }, .Interrupt, 0, 0b1000);
    for (idt[1..32], 1..) |*entry, i| entry.* = InterruptDescriptor.init(switch (i) {
        8, 10...14, 17, 30 => .{ .err = &handler_err },
        else => .{ .noerr = &handler_noerr },
    }, .Interrupt, 0, 0b1000);
    idtr.offset = @intFromPtr(&idt);
    const ptr: *const IDTR = &idtr;
    asm volatile (
        \\ lidt (%%eax)
        \\ sti
        :
        : [ptr] "{eax}" (ptr),
    );
}
