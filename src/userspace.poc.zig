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

fn poc_signal(id: u32) linksection("userspace") callconv(.C) void {
    const str = "Signal handled\n";
    const c = id + '0';
    _ = syscall(.write, .{ &c, 1 });
    _ = syscall(.write, .{ str, str.len });
}

pub fn syscall(code: anytype, args: anytype) linksection(".userspace") i32 {
    const _code: u32 = switch (@typeInfo(@TypeOf(code))) {
        .@"enum", .enum_literal => @intFromEnum(@as(@import("syscall.zig").Code, code)),
        .int, .comptime_int => @intCast(code),
        else => @compileError("Invalid syscall code type"),
    };

    var _args: struct { ebx: i32 = 0, ecx: i32 = 0, edx: i32 = 0, esi: i32 = 0, edi: i32 = 0 } = .{};

    const regs = .{ "ebx", "ecx", "edx", "esi", "edi" };
    inline for (args, 0..) |arg, i| {
        @field(_args, regs[i]) = switch (@typeInfo(@TypeOf(arg))) {
            .int, .comptime_int => @intCast(arg),
            .pointer => @bitCast(@as(u32, @intFromPtr(arg))),
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

const signal = @import("task/signal.zig");

var byte: u8 linksection("userspace") = 0;
var byte_index: u5 linksection("userspace") = 0;

fn server_handler(id: u32) linksection("userspace") callconv(.C) void {
    byte |= @truncate((id - @intFromEnum(signal.Id.SIGUSR1)) << byte_index);
    byte_index += 1;
    if (byte_index == 8) {
        _ = syscall(.write, &.{ &byte, 1 });
        byte_index = 0;
        byte = 0;
    }
}

fn server() linksection(".userspace") void {
    _ = syscall(.signal, &.{ @intFromEnum(signal.Id.SIGUSR1), &server_handler });
    _ = syscall(.signal, &.{ @intFromEnum(signal.Id.SIGUSR2), &server_handler });
    while (true) {}
}

fn send_byte(pid: u32, c: u8) linksection(".userspace") void {
    for (0..8) |index| {
        _ = syscall(.kill, &.{ pid, @intFromEnum(signal.Id.SIGUSR1) + ((c >> @as(u3, @intCast(index))) & 1) });
        _ = syscall(.sleep, .{10});
    }
}

fn send(pid: u32, msg: []const u8) linksection(".userspace") void {
    for (msg) |c| {
        send_byte(pid, c);
    }
}

fn client(server_pid: u32) linksection(".userspace") void {
    send(server_pid, "le minitalk\n");
}

export fn _userland() linksection(".userspace") void {
    const pid = syscall(.fork, .{});
    if (pid == 0) {
        server();
    } else {
        client(@bitCast(pid));
    }

    _ = syscall(.exit, .{0});

    _ = syscall(.signal, &.{ 2, &poc_signal });
    _ = syscall(.kill, &.{ syscall(.getpid, &.{}), 2 });
    // while (true) {}
    _ = syscall(.write, &.{ "coucou\n", 7 });
    _ = syscall(.fork, .{});
    _ = syscall(.sleep, .{100});
    _ = syscall(.write, &.{ "bonjour\n", 8 });
    _ = syscall(.fork, .{});
    _ = syscall(.sleep, .{100});
    _ = syscall(.write, &.{ "salut\n", 6 });
    _ = syscall(.exit, .{42});
}
