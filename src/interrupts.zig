const cpu = @import("cpu.zig");
const gdt = @import("gdt.zig");
const pic = @import("drivers/pic/pic.zig");
const ft = @import("ft/ft.zig");
const logger = ft.log.scoped(.intr);

pub const InterruptFrame = extern struct {
    edi: u32,
    esi: u32,
    ebp: u32,
    edx: u32,
    ecx: u32,
    ebx: u32,
    eax: u32,
    code: u32,
    iret: IretFrame,

    pub const IretFrame = extern struct {
        ip: u32,
        cs: u32,
        flags: u32,
        sp: u32,
        ss: u32,
    };

    pub inline fn debug(self: InterruptFrame) void {
        logger.warn(
            \\
            \\edi: 0x{x:0>8}
            \\esi: 0x{x:0>8}
            \\ebp: 0x{x:0>8}
            \\edx: 0x{x:0>8}
            \\ecx: 0x{x:0>8}
            \\ebx: 0x{x:0>8}
            \\eax: 0x{x:0>8}
            \\code: 0x{x:0>8}
            \\ip: 0x{x:0>8}
            \\cs: 0x{x:0>8}
            \\flags: 0x{x:0>8}
            \\sp: 0x{x:0>8}
            \\ss: 0x{x:0>8}
        , .{
            self.edi,
            self.esi,
            self.ebp,
            self.edx,
            self.ecx,
            self.ebx,
            self.eax,
            self.code,
            self.iret.ip,
            self.iret.cs,
            self.iret.flags,
            self.iret.sp,
            self.iret.ss,
        });
    }
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
    Reserved_15 = 15,
    x87FloatingPointException = 16,
    AlignmentCheck = 17,
    MachineCheck = 18,
    SIMDFloatingPointException = 19,
    VirtualizationException = 20,
    ControlProtectionException = 21,
    Reserved_22 = 22,
    Reserved_23 = 23,
    Reserved_24 = 24,
    Reserved_25 = 25,
    Reserved_26 = 26,
    Reserved_27 = 27,
    HypervisorInjectionException = 28,
    VMMCommunicationException = 29,
    SecurityException = 30,
    Reserved_31 = 31,
};

var idt: [256]InterruptDescriptor = [_]InterruptDescriptor{.{}} ** 256;

const default_handlers: [256]Handler = b: {
    var array: [256]Handler = undefined;
    for (array[0..256], 0..) |*entry, i| {
        entry.* = switch (i) {
            0x20...0x30 => |id| default_handler(id, .irq),
            0x31...0xff => |id| default_handler(id, .interrupt),
            @intFromEnum(Exceptions.DoubleFault),
            @intFromEnum(Exceptions.InvalidTSS),
            @intFromEnum(Exceptions.SegmentNotPresent),
            @intFromEnum(Exceptions.StackSegmentFault),
            @intFromEnum(Exceptions.GeneralProtectionFault),
            @intFromEnum(Exceptions.PageFault),
            @intFromEnum(Exceptions.AlignmentCheck),
            @intFromEnum(Exceptions.SecurityException),
            => |id| default_handler(id, .except_err),
            else => |id| default_handler(@truncate(id), .except),
        };
    }
    break :b array;
};

pub fn init() void {
    logger.debug("Initializing idt...", .{});

    inline for (0..256) |i| set_intr_gate(@as(u8, @intCast(i)), default_handlers[i]);

    idtr.offset = @intFromPtr(&idt);
    cpu.load_idt(&idtr);
    logger.info("Idt initialized", .{});
    cpu.enable_interrupts();
    logger.info("Interrupts enabled", .{});
}

/// return the numeric id of an interrupt (which can be an Exception, pic.IRQ or an int)
fn get_id(obj: anytype) u8 {
    return switch (@typeInfo(@TypeOf(obj))) {
        .Int => |i| if (i.signedness == .unsigned and i.bits <= 8)
            @intCast(obj)
        else
            @compileError("Invalid interrupt type: " ++ @typeName(@TypeOf(obj))),
        .ComptimeInt => comptime if (obj >= 0 and obj < 256) obj else @compileError("Invalid interrupt value"),
        .Enum => switch (@TypeOf(obj)) {
            Exceptions => @intFromEnum(obj),
            pic.IRQ => pic.get_interrupt_id_from_irq(obj) catch unreachable,
            else => @compileError("Invalid interrupt type: " ++ @typeName(@TypeOf(obj))),
        },
        .EnumLiteral => b: {
            if (@hasField(Exceptions, @tagName(obj))) {
                break :b @intFromEnum(@as(Exceptions, obj));
            } else if (@hasField(pic.IRQ, @tagName(obj))) {
                break :b pic.get_interrupt_id_from_irq(@as(pic.IRQ, obj)) catch unreachable;
            } else @compileError("Invalid interrupt type: Bad enum literal");
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

pub const Stub = *const fn () callconv(.Naked) void;

pub const Handler = extern union {
    ptr: usize,
    raw_handler: Stub,

    const Self = @This();

    pub fn create(comptime f: *const fn (frame: InterruptFrame) callconv(.C) void, comptime has_error: bool) Self {
        const factory = comptime struct {
            pub fn raw_stub() callconv(.Naked) void {
                if (!has_error) asm volatile ("push $0");
                asm volatile (
                    \\push %%eax
                    \\push %%ebx
                    \\push %%ecx
                    \\push %%edx
                    \\push %%ebp
                    \\push %%esi
                    \\push %%edi
                    \\cld
                );
                asm volatile ("call *%[f]"
                    :
                    : [f] "r" (f),
                );
                asm volatile (
                    \\pop %%edi
                    \\pop %%esi
                    \\pop %%ebp
                    \\pop %%edx
                    \\pop %%ecx
                    \\pop %%ebx
                    \\pop %%eax
                    \\add $4, %%esp
                    \\iret
                );
            }
        };

        return Self{ .raw_handler = factory.raw_stub };
    }
};

pub fn default_handler(
    comptime id: u8,
    comptime t: enum { except, except_err, irq, interrupt },
) Handler {
    const handlers = struct {
        pub fn exception(_: InterruptFrame) callconv(.C) void {
            const e = @as(Exceptions, @enumFromInt(id));
            ft.log.err("exception {d} ({s}) unhandled", .{ id, @tagName(e) });
        }
        pub fn exception_err(_: InterruptFrame) callconv(.C) void {
            const e = @as(Exceptions, @enumFromInt(id));
            ft.log.err("exception {d} ({s}) unhandled: 0x{x}", .{ id, @tagName(e), 0 });
        }
        pub fn irq(_: InterruptFrame) callconv(.C) void {
            const _id = pic.get_irq_from_interrupt_id(id);
            pic.ack(_id);
            ft.log.scoped(.irq).err("{d} ({s}) unhandled", .{ @intFromEnum(_id), @tagName(_id) });
        }
        pub fn interrupt(_: InterruptFrame) callconv(.C) void {
            ft.log.scoped(.interrupt).err("{d} unhandled", .{id});
        }
    };
    return switch (t) {
        .except => Handler.create(&handlers.exception, false),
        .except_err => Handler.create(&handlers.exception_err, true),
        .irq => Handler.create(&handlers.irq, false),
        .interrupt => Handler.create(&handlers.interrupt, false),
    };
}
