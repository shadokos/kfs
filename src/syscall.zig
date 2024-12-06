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

pub fn init() void {
    interrupts.set_system_gate(0x80, interrupts.Handler.create(syscall_handler, false));
}
