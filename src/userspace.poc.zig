const paging = @import("memory/paging.zig");
const signal = @import("task/signal.zig");
const userspace = @import("task/userspace.zig");
const scheduler = @import("task/scheduler.zig");
const TaskDescriptor = @import("task/task.zig").TaskDescriptor;
const VirtualSpace = @import("memory/virtual_space.zig").VirtualSpace;
const RegionSet = @import("memory/region_set.zig").RegionSet;
const regions = @import("memory/regions.zig");

/// What the demo builtin hands to enter_demo. 'argv' points at the shell's own storage,
/// which outlives the call: spawn() switches to the new task immediately, so the strings
/// are copied to the user stack before the shell resumes.
pub const DemoRequest = struct {
    entry: usize,
    argv: []const []const u8,
};

/// Spawn trampoline for the demos. The Image is synthetic: there is no program header
/// table, so phdr_vaddr is 0 and no AT_PHDR (and other entry depending on it) are emitted.
pub fn enter_demo(data: usize) u8 {
    const req: *const DemoRequest = @ptrFromInt(data);

    const task = scheduler.get_current_task();
    task.init_vm() catch @panic("todo Failed to initialize userspace");

    const vm = task.vm.?;
    userspace.map_userspace(vm);

    const argv = TaskDescriptor.dupe_strings_z(req.argv) catch @panic("todo Failed to copy argv");

    const entry = userspace.prepare_entry(vm, .{
        .entry = req.entry,
        .phdr_vaddr = 0,
        .phentsize = 0,
        .phnum = 0,
    }, argv, &.{});

    // prepare_entry copied the strings onto the user stack, and iret_to is noreturn,
    // so release here: a defer would never run.
    TaskDescriptor.free_strings_z(argv);
    userspace.iret_to(entry);
}

fn poc_signal(id: u32) linksection(".userspace") callconv(.c) void {
    const str = " Signal handled\n";
    const c = id + '0';
    _ = syscall(.write, .{ 1, &c, 1 });
    _ = syscall(.write, .{ 1, str, str.len });
}

fn poc_sigaction(id: u32, _: *signal.siginfo_t, _: *void) linksection(".userspace") callconv(.c) void {
    const str = " Signal handled with sigaction\n";
    const c = id + '0';
    _ = syscall(.write, .{ 1, &c, 1 });
    _ = syscall(.write, .{ 1, str, str.len });
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
    // The kernel returns the result in eax and the errno in ebx. Fold that into the
    // usual negative-errno convention so callers keep a single value to test, without
    // losing which error it was.
    if (ebx != 0) return -@as(i32, @intCast(ebx));
    return res;
}

fn putchar(c: u8) linksection(".userspace") void {
    _ = syscall(.write, &.{ 1, &c, 1 });
}

fn putchar_fd(fd: i32, c: u8) linksection(".userspace") void {
    _ = syscall(.write, &.{ fd, &c, 1 });
}

fn putstr_fd(fd: i32, s: []const u8) linksection(".userspace") void {
    _ = syscall(.write, &.{ fd, s.ptr, s.len });
}

fn putstr(s: []const u8) linksection(".userspace") void {
    for (s) |c| {
        putchar(c);
    }
}

fn putnbr(n: anytype) linksection(".userspace") void {
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
    if (@divTrunc(unsigned, @as(IntType, 10)) != 0)
        putnbr(@divTrunc(unsigned, @as(IntType, 10)));
    putchar(@intCast((unsigned % 10) + '0'));
}

export fn userland_mmap() linksection(".userspace") void {
    _ = syscall(.sleep, .{200});

    putstr("mmap 3 anonymous pages\n");

    const addr: [*][4096]u8 = @ptrFromInt(@as(u32, @bitCast(syscall(.mmap, .{
        null,
        4096 * 3,
        @import("syscall/mmap.zig").Prot{ .PROT_WRITE = true, .PROT_READ = true },
        @import("syscall/mmap.zig").Flags{ .anonymous = true, .privacy = .Private },
        0,
        0,
    }))));

    putstr("write a small string in each one\n");

    @memcpy(addr[0][0..7], "page 1\n");
    @memcpy(addr[1][0..7], "page 2\n");
    @memcpy(addr[2][0..7], "page 3\n");

    putstr("print pages\n");

    putstr(addr[0][0..7]);
    putstr(addr[1][0..7]);
    putstr(addr[2][0..7]);
    putstr("\n");

    putstr("mmap a fixed page on the second page\n");

    _ = syscall(.mmap, .{
        @as(?*void, @ptrCast(&(addr[1]))),
        4096,
        @import("syscall/mmap.zig").Prot{ .PROT_WRITE = true, .PROT_READ = true },
        @import("syscall/mmap.zig").Flags{ .anonymous = true, .privacy = .Private, .fixed = true },
        0,
        0,
    });

    putstr("print pages\n");

    putstr(addr[0][0..7]);
    putstr(addr[1][0..7]);
    putstr(addr[2][0..7]);
    putstr("\n");

    putstr("remove read permission from the 3rd page with mprotect (should segfault)\n");

    // _ = syscall (.munmap, .{@as(?*void, @ptrCast(&(addr[1]))), 4096});
    _ = syscall(.mprotect, .{
        @as(?*void, @ptrCast(&(addr[2]))),
        4096,
        @import("syscall/mmap.zig").Prot{ .PROT_WRITE = false, .PROT_READ = false },
    });

    putstr("print pages\n");

    putstr(addr[0][0..7]);
    putstr(addr[1][0..7]);
    putstr(addr[2][0..7]);
    putstr("\n");
}

fn count() linksection(".userspace") void {
    var n: u32 = 0;
    while (true) : (n += 1) {
        _ = syscall(.sleep, .{200});
        putstr("         \r");
        putnbr(n);
    }
}

export fn userland_count() linksection(".userspace") void {
    const pid = syscall(.fork, .{});
    if (pid == 0) {
        count();
    }
    for (0..3) |_| {
        _ = syscall(.sleep, .{3000});
        putstr("\rSTOP");
        _ = syscall(.kill, .{ pid, @as(u32, @intFromEnum(signal.Id.SIGSTOP)) });
        _ = syscall(.sleep, .{2000});
        putstr("\rCONTINUE");
        _ = syscall(.sleep, .{200});
        _ = syscall(.kill, .{ pid, @as(u32, @intFromEnum(signal.Id.SIGCONT)) });
    }
    putchar('\n');
    _ = syscall(.exit, .{0});
}

var byte: u8 linksection(".userspace") = 0;
var byte_index: u5 linksection(".userspace") = 0;

fn server_handler(id: u32) linksection(".userspace") callconv(.c) void {
    // putstr("bonjour\n");
    byte |= @truncate((id - @intFromEnum(signal.Id.SIGUSR1)) << byte_index);
    byte_index += 1;
    if (byte_index == 8) {
        _ = syscall(.write, &.{ 1, &byte, 1 });
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
    _ = syscall(.sleep, .{100});
    send(server_pid, "le minitalk\n");
    _ = syscall(.sleep, .{100});
}

export fn userland_minitalk() linksection(".userspace") void {
    const pid = syscall(.fork, .{});
    if (pid == 0) {
        server();
    } else {
        client(@bitCast(pid));
    }
    _ = syscall(.exit, .{0});
}

export fn userland_sleep() linksection(".userspace") void {
    _ = syscall(.sleep, .{20000});
    _ = syscall(.exit, .{0});
}

export fn userland_fork() linksection(".userspace") void {
    putstr("before fork\n");
    var id: u32 = @intFromBool(syscall(.fork, .{}) != 0);
    _ = syscall(.sleep, .{100 * id});
    putstr("fork 1\n");
    id = 2 * id + @intFromBool(syscall(.fork, .{}) != 0);
    _ = syscall(.sleep, .{100 * id});
    putstr("fork 2\n");
    id = 2 * id + @intFromBool(syscall(.fork, .{}) != 0);
    _ = syscall(.sleep, .{100 * id});
    putstr("fork 3\n");
    id = 2 * id + @intFromBool(syscall(.fork, .{}) != 0);
    _ = syscall(.sleep, .{100 * id});
    putstr("fork 4\n");
    _ = syscall(.sleep, .{20000});
    _ = syscall(.exit, .{0});
}

const open = @import("syscall/open.zig");

export fn userland_io() linksection(".userspace") void {
    const fd = syscall(.open, .{
        "/bonjour".ptr,
        open.Flags{
            .openMode = .wronly,
            .create = true,
            .exclusive = true,
        },
        open.Mode{},
    });
    putnbr(fd);
    putstr_fd(fd, "AAAAAAAAAAAAAAAAAAAAAA\n");
    _ = syscall(.truncate, .{ "/bonjour", 10 });
    putstr_fd(fd, "BBBBBBBBBBBBBBBBBBBBBB\n");
    _ = syscall(.exit, .{0});
}

/// demo execve <path> [args...]
///
/// Unlike the other demos this one needs its own entry block, so it enters naked:
/// the block is addressed through esp, and a normal prologue has already moved it.
export fn userland_execve() linksection(".userspace") callconv(.naked) noreturn {
    asm volatile (
        \\ mov %esp, %ecx
        \\ push %ecx
        \\ call demo_execve
    );
}

export fn demo_execve(sp: [*]const usize) linksection(".userspace") callconv(.c) noreturn {
    // sysv entry block: argc, argv[argc], NULL, envp[], NULL, auxv
    const argc = sp[0];
    const argv: [*]const ?[*:0]const u8 = @ptrCast(sp + 1);
    const envp: [*:null]const ?[*:0]const u8 = @ptrCast(sp + 2 + argc);

    if (argc < 2) {
        putstr("usage: demo execve <path> [args...]\n");
        _ = syscall(.exit, .{1});
        unreachable;
    }

    // Our own argv[0] is the demo name, so hand the image argv[1..]: it gets the path
    // as its argv[0], like a shell would pass it.
    const err = syscall(.execve, .{
        argv[1].?,
        @as([*:null]const ?[*:0]const u8, @ptrCast(argv + 1)),
        envp,
    });

    // execve only comes back when it failed
    putstr("execve failed, errno ");
    putnbr(-err);
    putstr("\n");
    _ = syscall(.exit, .{1});
    unreachable;
}

/// Sessions and the controlling terminal, POSIX 11.1.3, from userspace. The
/// kernel shell cannot show this: the only session leader it has is itself.
export fn userland_ctty() linksection(".userspace") void {
    const path = "/dev/tty0";
    const flags = open.Flags{ .openMode = .read_write };

    // setsid refuses a process group leader, and the spawned job is one.
    putstr("job pid ");
    putnbr(syscall(.getpid, .{}));
    putstr(" pgid ");
    putnbr(syscall(.getpgid, .{0}));
    putstr("\n");

    const leader = syscall(.fork, .{});
    if (leader == 0) {
        const sid = syscall(.setsid, .{});
        putstr("leader pid ");
        putnbr(syscall(.getpid, .{}));
        putstr(" pgid ");
        putnbr(syscall(.getpgid, .{0}));
        putstr(" session ");
        putnbr(sid);

        const fd = syscall(.open, .{ path.ptr, flags, open.Mode{} });
        putstr(" fd ");
        putnbr(fd);

        var owner: i32 = -1;
        _ = syscall(.ioctl, .{ fd, TIOCGSID, &owner });
        putstr(" tiocgsid ");
        putnbr(owner);
        putstr("\n");

        // In the foreground group, so the leader's death should hang it up.
        if (syscall(.fork, .{}) == 0) {
            putstr("fg child pid ");
            putnbr(syscall(.getpid, .{}));
            putstr(" pgid ");
            putnbr(syscall(.getpgid, .{0}));
            putstr("\n");
            _ = syscall(.sleep, .{1500});
            putstr("BAD: foreground child outlived the hangup\n");
            _ = syscall(.exit, .{1});
        }

        _ = syscall(.sleep, .{300});
        _ = syscall(.exit, .{0});
    }

    _ = syscall(.sleep, .{2500});

    // A second session, to see whether the terminal came back.
    if (syscall(.fork, .{}) == 0) {
        _ = syscall(.setsid, .{});
        const fd = syscall(.open, .{ path.ptr, flags, open.Mode{} });

        var owner: i32 = -1;
        const answer = syscall(.ioctl, .{ fd, TIOCGSID, &owner });
        if (answer == 0 and owner == syscall(.getsid, .{0}))
            putstr("terminal released and taken again\n")
        else
            putstr("BAD: terminal still answers to the dead session\n");

        _ = syscall(.exit, .{0});
    }

    _ = syscall(.sleep, .{1000});
    _ = syscall(.exit, .{0});
}

const TIOCGSID: u32 = 0x5429;

/// Terminal access control, POSIX 11.1.4, from userspace. A child in a group of
/// its own reads, and SIGTTIN stops it.
export fn userland_jobctl() linksection(".userspace") void {
    const path = "/dev/tty0";
    const flags = open.Flags{ .openMode = .read_write };

    // setsid refuses a process group leader, hence the extra fork.
    if (syscall(.fork, .{}) != 0) {
        _ = syscall(.sleep, .{3000});
        _ = syscall(.exit, .{0});
    }

    _ = syscall(.setsid, .{});
    _ = syscall(.open, .{ path.ptr, flags, open.Mode{} });

    if (syscall(.fork, .{}) == 0) {
        // A group of its own is a background group.
        _ = syscall(.setpgid, .{ 0, 0 });
        _ = syscall(.sleep, .{200});

        var scratch: [1]u8 = undefined;
        const read_bytes = syscall(.read, .{ 0, &scratch, 1 });
        putstr("BAD: background read returned ");
        putnbr(read_bytes);
        putstr("\n");
        _ = syscall(.exit, .{1});
    }

    var status: u32 = 0;
    const who = syscall(.waitpid, .{ -1, &status, wait.WaitOptions{ .WUNTRACED = true } });

    putstr("child ");
    putnbr(who);
    putstr(" status ");
    putnbr(status & 0xff);
    putstr(" signal ");
    putnbr((status >> 8) & 0xff);
    putstr("\n");

    _ = syscall(.exit, .{0});
}

const wait = @import("task/wait.zig");
