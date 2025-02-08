const interrupts = @import("../interrupts.zig");
const ft = @import("ft");

pub const mcontext_t = interrupts.InterruptFrame;

pub const ucontext_t = extern struct {
    uc_link: ?*ucontext_t = null,
    // uc_sigmask : sigset_t,
    // uc_stack : stack_t,
    uc_mcontext: mcontext_t,
};

pub fn put_data_on_stack(context: *ucontext_t, data: []u8) []u8 {
    const aligned_stack = ft.mem.alignBackward(usize, context.uc_mcontext.iret.sp - data.len, 4);
    const sp: []u8 = @as([*]u8, @ptrFromInt(aligned_stack))[0..data.len];
    @memcpy(sp, data);
    context.uc_mcontext.iret.sp = @intFromPtr(sp.ptr);
    return sp;
}

pub fn put_on_stack(context: *ucontext_t, elem: anytype) *@TypeOf(elem) { // todo bound check
    const sp = ft.mem.alignBackward(usize, context.uc_mcontext.iret.sp - @sizeOf(@TypeOf(elem)), 4);
    @as(*@TypeOf(elem), @ptrFromInt(sp)).* = elem;
    context.uc_mcontext.iret.sp = sp;
    return @ptrFromInt(sp);
}

pub fn makecontext(context: *ucontext_t, ret_address: usize, f: usize, args: anytype) void {
    const tinfo = @typeInfo(@TypeOf(args));
    inline for (0..tinfo.@"struct".fields.len) |i| {
        _ = put_on_stack(context, args[tinfo.@"struct".fields.len - i - 1]);
    }
    context.uc_mcontext.iret.sp = @intFromPtr(put_on_stack(context, ret_address));
    context.uc_mcontext.iret.ip = f;
}
