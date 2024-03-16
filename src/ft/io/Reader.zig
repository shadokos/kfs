const ft = @import("../ft.zig");
const mem = ft.mem;

context: *const anyopaque,

readFn: *const fn (*const anyopaque, []u8) anyerror!usize,

const Self = @This();

pub fn discard(self: Self) anyerror!u64 {
    var buffer: [100]u8 = undefined;
    var ret: u64 = 0;
    while (true) {
        const tmp = try self.read(buffer[0..]);
        ret += tmp;
        if (tmp == 0)
            break;
    }
    return ret;
}

pub fn isBytes(self: Self, slice: []const u8) anyerror!bool {
    var ret = true;
    for (slice) |c| {
        ret = (ret and (try self.readByte()) == c);
    }
    return ret;
}

pub fn read(self: Self, buffer: []u8) anyerror!usize {
    return self.readFn(self.context, buffer);
}

pub fn readAll(self: Self, buffer: []u8) anyerror!usize {
    return self.readAtLeast(buffer, buffer.len);
}

pub fn readAllAlloc(self: Self, allocator: mem.Allocator, max_size: usize) anyerror![]u8 {
    var array = ft.ArrayList(u8).init(allocator);
    defer array.deinit();
    try self.readAllArrayList(&array, max_size);
    array.shrinkAndFree(array.slice.len);
    return array.toOwnedSlice();
}

pub fn readAllArrayList(self: Self, array_list: *ft.ArrayList(u8), max_append_size: usize) anyerror!void {
    return self.readAllArrayListAligned(1, array_list, max_append_size); // todo align
}

pub fn readAllArrayListAligned(
    self: Self,
    comptime alignment: ?u29,
    array_list: *ft.ArrayListAligned(u8, alignment),
    max_append_size: usize,
) anyerror!void {
    var buffer: [128]u8 = undefined;
    var remaining = max_append_size;

    while (true) {
        const size = try self.read(buffer[0..]);
        if (size == 0) {
            break;
        }
        try array_list.appendSlice(buffer[0..@min(size, remaining)]);
        if (remaining < size) {
            return error.StreamTooLong;
        }
        remaining -= size;
    }
}

pub fn readAtLeast(self: Self, buffer: []u8, len: usize) anyerror!usize {
    ft.debug.assert(len <= buffer.len);
    var ret: usize = 0;
    while (ret < len) {
        const tmp = try self.read(buffer[ret..]);
        ret += tmp;
        if (tmp == 0) {
            break;
        }
    }
    return ret;
}

// pub fn readBoundedBytes(self: Self, comptime num_bytes: usize) anyerror!std.BoundedArray(u8, num_bytes)

pub fn readByte(self: Self) anyerror!u8 {
    var buffer: [1]u8 = undefined;
    try self.readNoEof(buffer[0..]);
    return buffer[0];
}

pub fn readByteSigned(self: Self) anyerror!i8 {
    return @bitCast(try self.readByte());
}

pub fn readBytesNoEof(self: Self, comptime num_bytes: usize) anyerror![num_bytes]u8 {
    var ret: [num_bytes]u8 = undefined;
    try self.readNoEof(ret[0..]);
    return ret;
}

// pub fn readEnum(self: Self, comptime Enum: type, endian: std.builtin.Endian) anyerror!Enum

// pub inline fn readInt(self: Self, comptime T: type, endian: std.builtin.Endian) anyerror!T

// pub fn readIntoBoundedBytes(
//     self: Self,
//     comptime num_bytes: usize,
//     bounded: *std.BoundedArray(u8, num_bytes),
// ) anyerror!void;

pub fn readNoEof(self: Self, buf: []u8) anyerror!void {
    if ((try self.readAll(buf)) != buf.len) {
        return error.EndOfStream;
    }
}

// pub fn readStruct(self: Self, comptime T: type) anyerror!T

// pub fn readStructEndian(self: Self, comptime T: type, endian: std.builtin.Endian) anyerror!T

pub fn readUntilDelimiter(self: Self, buf: []u8, delimiter: u8) anyerror![]u8 {
    for (buf, 0..) |*c, i| {
        c.* = try self.readByte();
        if (c.* == delimiter) {
            return buf[0 .. i + 1];
        }
    }
    return error.StreamTooLong;
}

pub fn readUntilDelimiterAlloc(self: Self, allocator: mem.Allocator, delimiter: u8, max_size: usize) anyerror![]u8 {
    var array = ft.ArrayList(u8).init(allocator);
    defer array.deinit();
    try self.readUntilDelimiterArrayList(&array, delimiter, max_size);
    array.shrinkAndFree(array.slice.len);
    return array.toOwnedSlice();
}

pub fn readUntilDelimiterArrayList(
    self: Self,
    array_list: *ft.ArrayList(u8),
    delimiter: u8,
    max_size: usize,
) anyerror!void {
    array_list.shrinkRetainingCapacity(0);
    for (0..max_size) |_| {
        const c = try self.readByte();
        try array_list.append(c);
        if (c == delimiter) {
            return;
        }
    }
    return error.StreamTooLong;
}

// pub fn readUntilDelimiterOrEof(self: Self, buf: []u8, delimiter: u8) anyerror!?[]u8

// pub fn readUntilDelimiterOrEofAlloc(
//     self: Self,
//     allocator: mem.Allocator,
//     delimiter: u8,
//     max_size: usize,
// ) anyerror!?[]u8;

// pub fn readVarInt(
//     self: Self,
//     comptime ReturnType: type,
//     endian: std.builtin.Endian,
//     size: usize,
// ) anyerror!ReturnType;

const SkipBytesOptions = struct {
    buf_size: usize = 512,
};

pub fn skipBytes(self: Self, num_bytes: u64, comptime options: SkipBytesOptions) anyerror!void {
    var buffer: [options.buf_size]u8 = undefined;
    var remaining_bytes = num_bytes;
    while (remaining_bytes != 0) {
        const tmp = try self.read(buffer[0..@min(remaining_bytes, buffer.len)]);
        if (tmp == 0)
            break;
        remaining_bytes -|= tmp;
    }
}

pub fn skipUntilDelimiterOrEof(self: Self, delimiter: u8) anyerror!void {
    while (true) {
        const tmp = self.readByte() catch |e| switch (e) {
            error.EndOfStream => return,
            else => return e,
        };
        if (tmp == delimiter) {
            return;
        }
    }
}

pub fn streamUntilDelimiter(self: Self, writer: anytype, delimiter: u8, optional_max_size: ?usize) anyerror!void {
    if (optional_max_size) |max_size| {
        for (0..max_size) |_| {
            const c = try self.readByte();
            try writer.writeByte(c);
            if (c == delimiter) {
                return;
            }
        }
        return error.StreamTooLong;
    } else {
        while (true) {
            const c = try self.readByte();
            try writer.writeByte(c);
            if (c == delimiter) {
                return;
            }
        }
    }
}
