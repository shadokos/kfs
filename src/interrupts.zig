const cpu = @import("cpu.zig");
const gdt = @import("gdt.zig");
const pic = @import("drivers/pic/pic.zig");
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
    privilege: cpu.PrivilegeLevel = cpu.PrivilegeLevel.Supervisor,
    present: bool = false,
    offset_2: u16 = undefined,

    const Self = @This();

    pub fn init(offset: Handler, gate: GateType, privilege: cpu.PrivilegeLevel, selector: u16) Self {
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

pub const Exceptions = enum(u8) {
    DivisionError = 0,
    Debug = 1,
    NonMaskableInterrupt = 2,
    Breakpoint = 3,
    Overflow = 4,
    BoundRangeExceeded = 5,
    InvalidOpcode = 6,
    DeviceNotAvailable = 7,
    DoubleFault = 8,
    CoprocessorSegmentOverrun = 9,
    InvalidTSS = 10,
    SegmentNotPresent = 11,
    StackSegmentFault = 12,
    GeneralProtectionFault = 13,
    PageFault = 14,
    x87FloatingPointException = 16,
    AlignmentCheck = 17,
    MachineCheck = 18,
    SIMDFloatingPointException = 19,
    VirtualizationException = 20,
    ControlProtectionException = 21,
    HypervisorInjectionException = 28,
    VMMCommunicationException = 29,
    SecurityException = 30,
};

var idt: [256]InterruptDescriptor = [_]InterruptDescriptor{.{}} ** 256;

const default_handlers: [256]Handler = b: {
    comptime var array: [256]Handler = undefined;
    for (array[0..256], 0..) |*entry, i| {
        entry.* = switch (i) {
            31...255 => |id| default_handler(id, "unhandled", .except),
            @intFromEnum(Exceptions.DoubleFault),
            @intFromEnum(Exceptions.InvalidTSS),
            @intFromEnum(Exceptions.SegmentNotPresent),
            @intFromEnum(Exceptions.StackSegmentFault),
            @intFromEnum(Exceptions.GeneralProtectionFault),
            @intFromEnum(Exceptions.PageFault),
            @intFromEnum(Exceptions.AlignmentCheck),
            @intFromEnum(Exceptions.SecurityException),
            => |id| default_handler(id, "unhandled", .err),
            else => |id| default_handler(@truncate(id), "unhandled", .noerr),
        };
    }
    break :b array;
};

pub fn init() void {
    logger.debug("Initializing idt...", .{});

    inline for (0..256) |i| set_intr_gate(@as(u8, @intCast(i)), default_handlers[i]);

    pic.remap(0x20, 0x28);

    idtr.offset = @intFromPtr(&idt);
    cpu.load_idt(&idtr);
    cpu.enable_interrupts();
    logger.info("Idt initialized", .{});
}

/// return the numeric id of an interrupt (which can be an Exception, pic.IRQS or an int)
fn get_id(obj: anytype) u8 {
    return switch (@typeInfo(@TypeOf(obj))) {
        .Int => |i| if (i.signedness == .unsigned and i.bits <= 8)
            @intCast(obj)
        else
            @compileError("Invalid interrupt type: " ++ @typeName(@TypeOf(obj))),
        .ComptimeInt => comptime if (obj >= 0 and obj < 256) obj else @compileError("Invalid interrupt value"),
        .Enum => switch (@TypeOf(obj)) {
            Exceptions => @intFromEnum(obj),
            pic.IRQS => @as(u8, @intFromEnum(obj)) + 32,
            else => @compileError("Invalid interrupt type: " ++ @typeName(@TypeOf(obj))),
        },
        else => @compileError("Invalid interrupt type: " ++ @typeName(@TypeOf(obj))),
    };
}

pub fn set_trap_gate(id: anytype, handler: Handler) void {
    idt[get_id(id)] = InterruptDescriptor.init(
        handler,
        .Trap,
        cpu.PrivilegeLevel.Supervisor,
        gdt.get_selector(1, .GDT, cpu.PrivilegeLevel.Supervisor),
    );
}

pub fn set_intr_gate(id: anytype, handler: Handler) void {
    idt[get_id(id)] = InterruptDescriptor.init(
        handler,
        .Interrupt,
        cpu.PrivilegeLevel.Supervisor,
        gdt.get_selector(1, .GDT, cpu.PrivilegeLevel.Supervisor),
    );
}

pub fn set_system_gate(id: anytype, handler: Handler) void {
    idt[get_id(id)] = InterruptDescriptor.init(
        handler,
        .Trap,
        cpu.PrivilegeLevel.User,
        gdt.get_selector(1, .GDT, cpu.PrivilegeLevel.Supervisor),
    );
}

pub fn unset_gate(id: u8) void {
    idt[get_id(id)] = default_handlers[get_id(id)];
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
