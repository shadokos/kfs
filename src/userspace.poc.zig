const ft = @import("ft");
const paging = @import("memory/paging.zig");

pub const SigHandler = *fn () void;

var current_signal: ?SigHandler = null;

pub fn queue_signal(handler: SigHandler) void {
    current_signal = handler;
}

pub fn get_next_signal() ?SigHandler {
    defer current_signal = null;
    return current_signal;
}

fn poc_signal() linksection("userspace") void {
    const str = "Signal handled\n";
    _ = syscall(.write, .{ str, str.len });
}

pub fn syscall(code: anytype, args: anytype) linksection(".userspace") i32 {
    const _code: u32 = switch (@typeInfo(@TypeOf(code))) {
        .Enum, .EnumLiteral => @intFromEnum(@as(@import("syscall.zig").Code, code)),
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
    if (ebx != 0) return -1;
    return res;
}

export fn _userland() linksection(".userspace") void {
    // while (true) {}
    for (0..9) |_| {
        // if (i % 3 == 0) _ = syscall(.poc_raise, .{&poc_signal});
        _ = syscall(.write, &.{ "write from userspace\n", 21 });
        _ = syscall(.sleep, .{1000});
        // for (0..100000) |_| {
        //     asm volatile ("nop");
        // }
    }
    _ = syscall(.exit, .{});
}
