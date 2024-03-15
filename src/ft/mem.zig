const ft = @import("ft");

pub const Allocator = @import("mem/Allocator.zig");

pub fn len(value: anytype) usize {
    switch (@typeInfo(@TypeOf(value))) {
        .Pointer => |info| switch (info.size) {
            .Many => {
                const sentinel: *const info.child = @as(
                    *const info.child,
                    @ptrCast(
                        info.sentinel orelse @compileError(
                            "Invalid type for mem.len: " ++ @typeName(@TypeOf(value)) ++ " type has no sentinel",
                        ),
                    ),
                );
                return indexOfSentinel(info.child, sentinel.*, value);
            },
            .C => {
                return indexOfSentinel(info.child, 0, value);
            },
            else => @compileError("Invalid type for mem.len: " ++ @typeName(@TypeOf(value))),
        },
        else => @compileError("Invalid type for mem.len: " ++ @typeName(@TypeOf(value))),
    }
}

pub fn indexOfScalarPos(comptime T: type, slice: []const T, start_index: usize, value: T) ?usize {
    for (slice[start_index..], start_index..) |c, i| {
        if (c == value)
            return i;
    }
    return null;
}

pub fn indexOfScalar(comptime T: type, slice: []const T, value: T) ?usize {
    for (slice, 0..) |c, i| {
        if (c == value)
            return i;
    }
    return null;
}

pub fn indexOfLastScalar(comptime T: type, slice: []const T, value: T) ?usize {
    var i: usize = slice.len - 1;
    while (i > 0 and slice[i] != value) : (i -= 1) {}
    return if (slice[i] == value) i else null;
}

pub fn indexOfSentinel(comptime T: type, comptime sentinel: T, p: [*:sentinel]const T) usize {
    var i: usize = 0;
    while (p[i] != sentinel) : (i += 1) {}
    return i;
}

pub fn eql(comptime T: type, a: []const T, b: []const T) bool {
    var i: usize = 0;
    if (a.len != b.len)
        return false;
    while (i < a.len and i < b.len and a[i] == b[i]) : (i += 1) {}
    return i == a.len;
}

pub fn copyForwards(comptime T: type, dest: []T, src: []const T) void {
    for (dest[0..src.len], src) |*d, s| d.* = s;
}

pub fn alignBackward(comptime T: type, addr: T, alignment: T) T {
    return addr & ~(alignment - 1);
}

pub fn alignForward(comptime T: type, addr: T, alignment: T) T {
    return alignBackward(T, addr + (alignment - 1), alignment);
}

pub fn isAligned(addr: usize, alighment: usize) bool {
    return addr & ~(alighment - 1) == addr;
}

pub fn swap(comptime T: type, a: *T, b: *T) void {
    const tmp: T = a.*;
    a.* = b.*;
    b.* = tmp;
}
