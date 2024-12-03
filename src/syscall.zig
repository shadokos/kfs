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
    Kill = 1,
    Sigreturn = 2,
    // Write ne devrait normalement pas fonctionner
    Write = 3,
    // DebugSyscall printk errno et la valeur passé à eax (supposé être le retour d'un syscall)
    DebugSyscall = 4,
};

// TODO: Put this function into the intergalactic void
fn debug_syscall(ret: i32) u8 {
    tty.printk("errno: {d}, ret: {d}\n", .{ errno.errno, ret });
    return 0;
}

pub fn syscall_handler(fr: *interrupts.InterruptFrame) callconv(.C) void {
    const code: Code = std.meta.intToEnum(Code, fr.eax) catch {
        syscall_logger.debug("Unknown call ({d})", .{fr.eax});
        fr.eax = errno.Error.ENOSYS.cast();
        return;
    };

    fr.eax = switch (code) {
        .Sleep => @import("syscall/sleep.zig").sys_sleep(fr.ebx),
        .Kill => @import("syscall/kill.zig").sys_kill(fr),
        .Sigreturn => @import("syscall/kill.zig").sys_sigreturn(fr),
        .Write => @import("syscall/write.zig").sys_write(@as([*]const u8, @ptrFromInt(fr.ebx)), fr.ecx),
        .DebugSyscall => debug_syscall(@bitCast(fr.ebx)),
        // else => syscall_logger.debug("not implemented yet ({d})", .{@intFromEnum(sys_num)}),
    };
}

// TODO: Discuss about this implementation :eyes:
// Ptdrrrr, hum, je fais des tests hein, chapo chapooo
// Mais dans l'idée, le but ici c'est de pouvoir syscall avec un code ou un enum, et une liste d'arguments
// Ça rends l'utilisation un peu plus simple: syscall(.Sleep, .{1_000}); syscall(.Write, .{buffer, len});
// Mais jui pas un foufou du zigou, donc j'attends d'en discuter avec toi
//
// Sinon, on peut également partir sur plusieurs fonctions syscall,
// par exemple, dans linux, plusieurs macros syscall sont définies: syscall0, syscall1, syscall2, etc...
// Ça rendrait la fonction certainement moins complexe et plus réactive
// + le fait qu'ici, baaah on set quand meme tous les registres bien qu'ils ne soient pas spécialement utilisés
//
// On peut éventuellement voir si c'est possible de mettre en place une factory ?
pub fn syscall(code: anytype, args: anytype) linksection(".userspace") i32 {
    const _code: u32 = switch (@typeInfo(@TypeOf(code))) {
        .Enum, .EnumLiteral => @intFromEnum(@as(Code, code)),
        .Int, .ComptimeInt => @intCast(code),
        else => @compileError("Invalid syscall code type"),
    };
    // ici, j'utilise i32, sinon impossible de passer un int negatif en argument,
    // car impossible de @bitCast un comptime_int
    // (donc pas possible a priori de passer un comptime_int u32 en comptime_int i32)
    var _args: struct { ebx: i32 = 0, ecx: i32 = 0, edx: i32 = 0, esi: i32 = 0, edi: i32 = 0 } = .{};

    const regs = .{ "ebx", "ecx", "edx", "esi", "edi" };
    inline for (args, 0..) |arg, i| {
        @field(_args, regs[i]) = switch (@typeInfo(@TypeOf(arg))) {
            .Int, .ComptimeInt => @intCast(arg),
            .Pointer => @bitCast(@as(u32, @intFromPtr(arg))),
            else => @compileError("Invalid syscall argument type"),
        };
    }

    var res: i32 = @bitCast(asm volatile ("int $0x80"
        : [_] "={eax}" (-> i32),
        : [_] "{eax}" (_code),
          [_] "{ebx}" (_args.ebx),
          [_] "{ecx}" (_args.ecx),
          [_] "{edx}" (_args.edx),
          [_] "{esi}" (_args.esi),
          [_] "{edi}" (_args.edi),
    ));
    if (res < 0) {
        errno.errno = -res;
        res = -1;
    }
    return res;
}

pub fn init() void {
    interrupts.set_system_gate(0x80, interrupts.Handler.create(syscall_handler, false));
}
