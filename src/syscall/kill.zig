const ft = @import("../ft/ft.zig");
const interrupts = @import("../interrupts.zig");

var current_frame: interrupts.InterruptFrame = undefined;

fn setup_frame(frame: *interrupts.InterruptFrame) void {
    current_frame = frame.*;

    const handler_ptr = &@import("../task/task.zig").sighandler;

    frame.iret.ip = @intFromPtr(handler_ptr);
    const bytecode = "\xb8\x77\x00\x00\x00\xcd\x80";
    const bytecode_begin: [*]align(4) u8 = @ptrFromInt(
        frame.iret.sp - 4 - ft.mem.alignForward(
            usize,
            bytecode.len,
            4,
        ),
    );
    @memcpy(bytecode_begin[0..bytecode.len], bytecode);
    const stack: [*]u32 = @as([*]u32, @ptrCast(bytecode_begin)) - 2;
    stack[1] = 42;
    stack[0] = @intFromPtr(bytecode_begin);
    frame.iret.sp = @intFromPtr(stack);
}

pub fn do_signal(frame: *interrupts.InterruptFrame) void {
    // Todo: chepo, des trucs certainement
    setup_frame(frame);
}

pub fn sigreturn(frame: *interrupts.InterruptFrame) void {
    frame.* = current_frame;
}