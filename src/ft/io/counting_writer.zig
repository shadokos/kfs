const ft = @import("../ft.zig");

pub fn CountingWriter(comptime WriterType: type) type {
    return struct {
        child_stream: WriterType,
        bytes_written: usize = 0,

        pub const Writer = ft.io.Writer(*Self, Error, write);
        pub const Error = WriterType.Error;

        pub const Self = @This();

        pub fn write(self: *Self, bytes: []const u8) Error!usize {
            const n = try self.child_stream.write(bytes);
            self.bytes_written += n;
            return n;
        }

        pub fn writer(self: *Self) Writer {
            return .{
                .context = self,
            };
        }
    };
}

pub fn countingWriter(child_stream: anytype) CountingWriter(@TypeOf(child_stream)) {
    return .{
        .child_stream = child_stream,
    };
}
