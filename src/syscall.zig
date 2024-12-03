const interrupts = @import("interrupts.zig");
const tty = @import("./tty/tty.zig");
const ft = @import("ft/ft.zig");
const std = @import("std");
const log = @import("ft/ft.zig").log;

const syscall_logger = log.scoped(.syscall);

// Todo: Maybe found a better name for this enum
pub const Num = enum(u8) {
    NanoSleep = 162,
    Kill = 37,
    Sigreturn = 119,
};

pub fn syscall_handler(fr: *interrupts.InterruptFrame) callconv(.C) void {
    const sys_num: Num = std.meta.intToEnum(Num, fr.eax) catch {
        syscall_logger.debug("Unknown syscall: {}", .{fr.eax});
        return;
    };

    switch (sys_num) {
        .NanoSleep => {
            syscall_logger.debug("syscall: nanosleep({d})", .{fr.ebx});
            @import("syscall/nanosleep.zig").sys_nanosleep(fr.ebx);
        },
        .Kill => @import("syscall/kill.zig").do_signal(fr),
        .Sigreturn => @import("syscall/kill.zig").sigreturn(fr),
        //else => syscall_logger.debug("not implemented yet ({d})", .{@intFromEnum(sys_num)}),
    }
}

// var current_frame: interrupts.InterruptFrame = undefined;
//
// pub fn syscall_handler(fr: *interrupts.InterruptFrame) callconv(.C) void {
//     tty.printk("eax: {}\n", .{fr.eax});
//     tty.printk("esp: {x:0>8}\n", .{fr.iret.sp});
//     tty.printk("eip: {x:0>8}\n", .{fr.iret.ip});
//
//
//     if (fr.eax == 1) {
//         current_frame = fr.*;
//
//         const handler_ptr = &@import("task/task.zig").sighandler;
//
//         fr.iret.ip = @intFromPtr(handler_ptr);
//         const bytecode = "\xb8\x2b\x00\x00\x00\xcd\x80";
//         const bytecode_begin: [*]align(4) u8 = @ptrFromInt(
//             fr.iret.sp - 4 - ft.mem.alignForward(
//                 usize,
//                 bytecode.len,
//                 4,
//             ),
//         );
//         @memcpy(bytecode_begin[0..bytecode.len], bytecode);
//         const stack: [*]u32 = @as([*]u32, @ptrCast(bytecode_begin)) - 2;
//         stack[1] = 42;
//         stack[0] = @intFromPtr(bytecode_begin);
//         fr.iret.sp = @intFromPtr(stack);
//         return;
//     } else if (fr.eax == 43) {
//         fr.* = current_frame;
//         tty.printk("-> esp: {x:0>8}\n", .{fr.iret.sp});
//         tty.printk("-> eip: {x:0>8}\n", .{fr.iret.ip});
//         return;
//     } else if (fr.eax == 2) {
//         // sleep syscall
//         tty.printk("sleeping for {d} ms\n", .{fr.ebx});
//         @import("drivers/pit/pit.zig").sleep(fr.ebx);
//     }
// }

const syscall_args = struct {
    eax: u32 = 0,
    ebx: u32 = 0,
    ecx: u32 = 0,
    edx: u32 = 0,
};

pub fn syscall(args: syscall_args) linksection(".userspace") u32 {
    return asm ("int $0x80"
        : [_] "={eax}" (-> u32),
        : [_] "{eax}" (args.eax),
          [_] "{ebx}" (args.ebx),
    );
}

pub fn init() void {
    interrupts.set_system_gate(0x80, interrupts.Handler.create(syscall_handler, false));
}

// TODO: Move the following functions on a unift.zig or something
pub fn nanosleep(ns: u32) void {
    _ = syscall(.{.eax = @intFromEnum(Num.NanoSleep), .ebx = ns});
}

// pub fn kill() blablabla
// etc...
