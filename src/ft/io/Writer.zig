const ft = @import("../ft.zig");

context: *const anyopaque,
writeFn: *const fn (*const anyopaque, []const u8) anyerror!usize,

const Self = @This();

pub fn print(self: Self, comptime format: []const u8, args: anytype) anyerror!void {
    return ft.fmt.format(self, format, args);
}

pub fn write(self: Self, bytes: []const u8) anyerror!usize {
    return self.writeFn(self.context, bytes);
}

pub fn writeAll(self: Self, bytes: []const u8) anyerror!void {
    var offset: usize = 0;
    while (offset != bytes.len) {
        offset += try self.write(bytes[offset..]);
    }
}

pub fn writeByte(self: Self, byte: u8) anyerror!void {
    return self.writeAll(&([1]u8{byte}));
}
