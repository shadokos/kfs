const ft = @import("ft");
const paging = @import("memory/paging.zig");
const signal = @import("task/signal.zig");

fn poc_signal(id: u32) linksection(".userspace") callconv(.C) void {
    const str = " Signal handled\n";
    const c = id + '0';
    _ = syscall(.write, .{ &c, 1 });
    _ = syscall(.write, .{ str, str.len });
}

fn poc_sigaction(id: u32, _: *signal.siginfo_t, _: *void) linksection(".userspace") callconv(.C) void {
    const str = " Signal handled with sigaction\n";
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

    var _args: struct { ebx: i32 = 0, ecx: i32 = 0, edx: i32 = 0, esi: i32 = 0, edi: i32 = 0, ebp: i32 = 0 } = .{};

    const regs = .{ "ebx", "ecx", "edx", "esi", "edi", "ebp" };
    inline for (args, 0..) |arg, i| {
        @field(_args, regs[i]) = switch (@typeInfo(@TypeOf(arg))) {
            .int, .comptime_int => @intCast(arg),
            .pointer => @bitCast(@as(u32, @intFromPtr(arg))),
            .optional => |opt| switch (@typeInfo(opt.child)) {
                .pointer => @bitCast(@as(u32, @intFromPtr(arg))),
                else => @compileError("Invalid syscall argument type"),
            },
            .null => 0,
            .@"struct" => |s| switch (s.layout) {
                .@"packed" => @bitCast(@as(u32, @intCast(@as(s.backing_integer.?, @bitCast(arg))))),
                else => @compileError("Invalid syscall argument type"),
            },
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

var byte: u8 linksection(".userspace") = 0;
var byte_index: u5 linksection(".userspace") = 0;

fn server_handler(id: u32) linksection(".userspace") callconv(.C) void {
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

fn putchar(c: u8) void {
    _ = syscall(.write, &.{ &c, 1 });
}

fn putstr(s: []const u8) void {
    for (s) |c| {
        putchar(c);
    }
}

fn putnbr(n: anytype) void {
    const NTypeInfo = @typeInfo(@TypeOf(n));
    const IntType = @import("std").meta.Int(
        .unsigned,
        NTypeInfo.int.bits + @intFromBool(NTypeInfo.int.signedness == .signed),
    );
    const unsigned: IntType = if (n < 0) b: {
        putchar('-');
        break :b @intCast(-n);
    } else @intCast(n);
    if (unsigned == 0) {
        putchar('0');
        return;
    }
    putnbr(@as(IntType, unsigned / @as(IntType, 10)));
    putchar(@intCast((unsigned % 10) + '0'));
}

fn test_segfault() linksection(".userspace") void {
    _ = syscall(.sleep, .{200});
    const addr: [*][4096]u8 = @ptrFromInt(@as(u32, @bitCast(syscall(.mmap, .{
        null,
        4096 * 3,
        @import("syscall/mmap.zig").Prot{ .PROT_WRITE = true, .PROT_READ = true },
        @import("syscall/mmap.zig").Flags{ .anonymous = true, .privacy = .Private },
        0,
        0,
    }))));
    @memcpy(addr[0][0..8], "bonjour\n");
    @memcpy(addr[1][0..8], "bonjour\n");
    @memcpy(addr[2][0..8], "bonjour\n");

    putstr(addr[0][0..8]);
    putstr(addr[1][0..8]);
    putstr(addr[2][0..8]);
    putstr("\n");

    _ = syscall(.mmap, .{
        @as(?*void, @ptrCast(&(addr[1]))),
        4096,
        @import("syscall/mmap.zig").Prot{ .PROT_WRITE = true, .PROT_READ = true },
        @import("syscall/mmap.zig").Flags{ .anonymous = true, .privacy = .Private, .fixed = true },
        0,
        0,
    });

    putstr(addr[0][0..8]);
    putstr(addr[1][0..8]);
    putstr(addr[2][0..8]);
    putstr("\n");

    // _ = syscall (.munmap, .{@as(?*void, @ptrCast(&(addr[1]))), 4096});
    _ = syscall(.mprotect, .{
        @as(?*void, @ptrCast(&(addr[0]))),
        4096,
        @import("syscall/mmap.zig").Prot{ .PROT_WRITE = false, .PROT_READ = false },
    });

    putstr(addr[0][0..8]);
    putstr(addr[1][0..8]);
    putstr(addr[2][0..8]);
    putstr("\n");
}

fn count() void {
    var n: u32 = 0;
    while (true) : (n += 1) {
        _ = syscall(.sleep, .{200});
        putnbr(n);
        putchar('\n');
    }
}

fn launch_count() void {
    const pid = syscall(.fork, .{});
    if (pid == 0) {
        count();
    }
    while (true) {
        _ = syscall(.sleep, .{3000});
        putstr("STOP\n");
        _ = syscall(.kill, .{ pid, @as(u32, @intFromEnum(signal.Id.SIGSTOP)) });
        _ = syscall(.sleep, .{2000});
        putstr("CONT\n");
        _ = syscall(.kill, .{ pid, @as(u32, @intFromEnum(signal.Id.SIGCONT)) });
    }
}

fn zig_userland() linksection(".userspace") void {
    // launch_count();

    {
        const pid = syscall(.fork, .{});
        if (pid == 0) {
            test_segfault();
            _ = syscall(.exit, .{42});
        }

        const Status = @import("task/wait.zig").Status;

        var status: Status = undefined;

        // const WaitOptions = @import("task/wait.zig").WaitOptions;
        // const wait_ret : i32 = syscall(.waitpid, .{pid, &status, WaitOptions{}});
        const wait_ret: i32 = syscall(.wait, .{&status});

        putnbr(wait_ret);
        putchar('\n');
        if (wait_ret > 0) {
            putstr("process ");
            putnbr(wait_ret);
            switch (status.type) {
                .Exited => {
                    putstr(" exited with exit code ");
                    putnbr(status.value);
                },
                .Continued => putstr(" continued"),
                .Stopped => putstr(" stopped"),
                .Signaled => {
                    putstr(" received signal ");
                    putnbr(status.value);
                },
            }
            putchar('\n');
        }

        _ = syscall(.exit, .{0});
    }

    const sigaction = @import("task/signal.zig").Sigaction{ .sa_sigaction = &poc_sigaction, .sa_flags = .{
        .SA_SIGINFO = true,
    } };
    _ = syscall(.sigaction, &.{ 2, &sigaction, null });
    // _ = syscall(.signal, &.{ 2, &poc_signal });
    _ = syscall(.kill, &.{ syscall(.getpid, &.{}), 2 });
    {
        const pid = syscall(.fork, .{});
        if (pid == 0) {
            server();
        } else {
            client(@bitCast(pid));
        }
    }

    _ = syscall(.exit, .{0});

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

export fn _userland() linksection(".userspace") void {
    zig_userland();
}
