const cpu = @import("cpu.zig");
const interrupt_logger = @import("ft/ft.zig").log.scoped(.interrupts);
const logger = @import("ft/ft.zig").log.scoped(.idt);

pub const Handler = extern union {
    ptr: usize,
    err: *const fn (u32) callconv(.Interrupt) void,
    noerr: *const fn () callconv(.Interrupt) void,
};

pub const IDTR = packed struct {
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
    gate: GateType = .Interrupt,
    privilege: u2 = 0,
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
var default_handlers: [256]Handler = undefined;

pub fn init() void {
    logger.debug("Initializing idt...", .{});

    inline for (default_handlers[0..256], 0..) |*entry, i| {
        entry.* = switch (i) {
            inline 31...255 => |id| default_handler(id, "unhandled", .except),
            inline 8, 10...14, 17, 30 => |id| default_handler(id, "unhandled", .err),
            inline else => |id| default_handler(@truncate(id), "unhandled", .noerr),
        };
    }

    inline for (idt[0..256], 0..) |*entry, i| entry.* = InterruptDescriptor.init(
        default_handlers[i],
        .Interrupt,
        0,
        0b1000,
    );
    idt[33] = InterruptDescriptor.init(
        .{ .noerr = @import("tty/keyboard.zig").handler },
        .Interrupt,
        0,
        0b1000,
    );

    @import("drivers/pic/pic.zig").remap(0x20, 0x28);
    @import("drivers/pic/pic.zig").enable_irq(.Keyboard);

    idtr.offset = @intFromPtr(&idt);
    cpu.load_idt(&idtr);
    cpu.enable_interrupts();
    logger.info("Idt initialized", .{});
}

pub fn default_handler(
    comptime id: u8,
    comptime name: []const u8,
    comptime t: enum { err, noerr, except },
) Handler {
    const handlers = struct {
        pub fn exception() callconv(.Interrupt) void {
            interrupt_logger.err("exception {d}, {s}", .{ id, name });
            @import("drivers/pic/pic.zig").ack();
        }
        pub fn noerr() callconv(.Interrupt) void {
            @import("ft/ft.zig").log.err("irq {d}, {s}", .{ id, name });
        }
        pub fn err(code: u32) callconv(.Interrupt) void {
            @import("ft/ft.zig").log.err("irq {d}, {s}, 0x{x}", .{ id, name, code });
        }
    };
    return switch (t) {
        .err => .{ .err = &handlers.err },
        .noerr => .{ .noerr = &handlers.noerr },
        .except => .{ .noerr = &handlers.exception },
    };
}
