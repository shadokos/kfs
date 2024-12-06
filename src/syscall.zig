const interrupts = @import("interrupts.zig");
const tty = @import("./tty/tty.zig");
const ft = @import("ft/ft.zig");
const std = @import("std");
const log = @import("ft/ft.zig").log;
const errno = @import("errno.zig");

const syscall_logger = log.scoped(.syscall);

// Todo: Maybe found a better name for this enum
// /!\ these syscalls are dummy ones for the example
pub const Code = enum(u8) {
    Sleep = 0,
};

// TODO: Put this function into the intergalactic void
fn debug_syscall(ret: i32) u8 {
    tty.printk("ret: {d}, errno: {d}\n", .{ ret, errno.errno });
    return 0;
}

pub fn syscall_handler(fr: *interrupts.InterruptFrame) callconv(.C) void {
    const code: Code = std.meta.intToEnum(Code, fr.eax) catch {
        syscall_logger.debug("Unknown call ({d})", .{fr.eax});
        fr.ebx = errno.error_num(errno.Errno.ENOSYS);
        return;
    };
    if (switch (code) {
        .Sleep => @import("syscall/sleep.zig").sys_sleep(fr.ebx),
        // else => syscall_logger.debug("not implemented yet ({d})", .{@intFromEnum(sys_num)}),
    }) |v| {
        fr.eax = v;
        fr.ebx = 0;
    } else |e| {
        if (errno.is_in_set(e, errno.Errno)) {
            fr.ebx = errno.error_num(e);
        } else syscall_logger.err("unhandled error: {s}", .{@errorName(e)});
    }
}

pub fn syscall(code: anytype, args: anytype) linksection(".userspace") i32 {
    const _code: u32 = switch (@typeInfo(@TypeOf(code))) {
        .Enum, .EnumLiteral => @intFromEnum(@as(Code, code)),
        .Int, .ComptimeInt => @intCast(code),
        else => @compileError("Invalid syscall code type"),
    };

    var _args: struct { ebx: i32 = 0, ecx: i32 = 0, edx: i32 = 0, esi: i32 = 0, edi: i32 = 0 } = .{};

    const regs = .{ "ebx", "ecx", "edx", "esi", "edi" };
    inline for (args, 0..) |arg, i| {
        @field(_args, regs[i]) = switch (@typeInfo(@TypeOf(arg))) {
            .Int, .ComptimeInt => @intCast(arg),
            .Pointer => @bitCast(@as(u32, @intFromPtr(arg))),
            else => @compileError("Invalid syscall argument type"),
        };
    }

    var ebx: u32 = 0;
    const res: i32 = @bitCast(asm volatile ("int $0x80"
        : [_] "={ebx}" (ebx),
          [_] "={eax}" (-> i32),
        : [_] "{eax}" (_code),
          [_] "{ebx}" (_args.ebx),
          [_] "{ecx}" (_args.ecx),
          [_] "{edx}" (_args.edx),
          [_] "{esi}" (_args.esi),
          [_] "{edi}" (_args.edi),
    ));
    if (ebx != 0) {
        errno.errno = ebx;
        return -1;
    }
    return res;
}

pub fn init() void {
    interrupts.set_system_gate(0x80, interrupts.Handler.create(syscall_handler, false));
}
