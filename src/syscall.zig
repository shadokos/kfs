const interrupts = @import("interrupts.zig");
const tty = @import("./tty/tty.zig");
const ft = @import("ft/ft.zig");
const std = @import("std");
const syscall_table = @import("syscall_table.zig");
const log = @import("ft/ft.zig").log;
const errno = @import("errno.zig");

const syscall_logger = log.scoped(.syscall);

pub fn syscall_enum(comptime T: type) type {
    const decls: []const std.builtin.Type.Declaration = @typeInfo(T).Struct.decls;
    comptime var enumFields: [decls.len]std.builtin.Type.EnumField = undefined;
    for (decls, enumFields[0..]) |d, *f| {
        f.name = d.name;
        f.value = @field(T, d.name).Id;
    }
    return @Type(.{ .Enum = .{
        .tag_type = usize,
        .fields = enumFields[0..],
        .decls = &.{},
        .is_exhaustive = true,
    } });
}

// Todo: Maybe found a better name for this enum
// /!\ these syscalls are dummy ones for the example
pub const Code = syscall_enum(syscall_table); // todo implement in ft

fn get_fn_proto_tuple(comptime proto: std.builtin.Type.Fn) type {
    comptime var fields: [proto.params.len]std.builtin.Type.StructField = undefined;

    for (proto.params, fields[0..], 0..) |p, *f, i| {
        f.* = .{
            .name = &.{'0' + i},
            .type = p.type.?,
            .default_value = null,
            .is_comptime = false,
            .alignment = @alignOf(p.type.?),
        };
    }
    return @Type(.{ .Struct = .{
        .layout = .auto,
        .backing_integer = null,
        .fields = fields[0..],
        .decls = &.{},
        .is_tuple = true,
    } });
}

fn convert_param(comptime T: type, reg: usize) T {
    if (@typeInfo(T) == .Pointer) {
        return @ptrFromInt(reg);
    } else {
        return @bitCast(@as(
            std.meta.Int(.unsigned, @bitSizeOf(T)),
            @truncate(reg),
        ));
    }
}

fn convert_ret(comptime T: type, val: T) usize {
    if (@typeInfo(T) == .Pointer) {
        return @intFromPtr(val);
    } else {
        return @intCast(@as(
            std.meta.Int(.unsigned, @bitSizeOf(T)),
            @bitCast(val),
        ));
    }
}

fn call_syscall(comptime code: Code, fr: interrupts.InterruptFrame) !usize {
    const do_fn = @field(syscall_table, @tagName(code)).do;
    const proto: std.builtin.Type.Fn = @typeInfo(@TypeOf(do_fn)).Fn;

    if (proto.params.len > 6)
        @compileError("syscall cannot have more than 6 parameter: " ++ @tagName(code));

    const TupleType = get_fn_proto_tuple(proto);
    var tuple: TupleType = undefined;
    const param_register = [_][]const u8{ "ebx", "ecx", "edx", "esi", "edi", "ebp" };
    inline for (0..tuple.len) |i| {
        const reg = @field(fr, param_register[i]);
        tuple[i] = convert_param(@TypeOf(tuple[i]), reg);
    }

    const ret: proto.return_type.? = @call(.auto, do_fn, tuple);

    if (ret) |v| {
        return if (comptime @TypeOf(v) != void)
            convert_ret(@TypeOf(v), v)
        else
            0;
    } else |e| return e;
}

pub fn syscall_handler(fr: *interrupts.InterruptFrame) callconv(.C) void {
    const code: Code = std.meta.intToEnum(Code, fr.eax) catch {
        syscall_logger.debug("Unknown call ({d})", .{fr.eax});
        fr.ebx = errno.error_num(errno.Errno.ENOSYS);
        return;
    };
    if (switch (code) {
        inline else => |c| call_syscall(c, fr.*),
    }) |v| {
        fr.eax = v;
        fr.ebx = 0;
    } else |e| if (errno.is_in_set(e, errno.Errno)) {
        fr.ebx = errno.error_num(e);
    } else syscall_logger.err("unhandled error: {s}", .{@errorName(e)});
}

pub fn init() void {
    interrupts.set_system_gate(0x80, interrupts.Handler.create(syscall_handler, false));
}
