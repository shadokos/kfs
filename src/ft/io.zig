const ft = @import("ft.zig");

pub fn GenericReader(
    comptime Context: type,
    comptime ReadError: type,
    comptime readFn: fn (Context, []u8) ReadError!usize,
) type {
    return struct {
        context: Context,

        const Self = @This();

        const Error = ReadError;

        pub fn read(self: Self, bytes: []u8) Error!usize {
            self.any().read(bytes);
        }

        pub fn readAll(self: Self, bytes: []u8) Error!void {
            self.any().readAll(bytes);
        }

        pub fn readByte(self: Self, byte: u8) Error!void {
            self.any().readByte(byte);
        }

        // https://github.com/ziglang/zig/blob/master/lib/std/io.zig
        pub inline fn any(self: *const Self) AnyReader {
            return .{
                .context = @ptrCast(&self.context),
                .readFn = typeErasedReadFn,
            };
        }

        // https://github.com/ziglang/zig/blob/master/lib/std/io.zig
        fn typeErasedReadFn(context: *const anyopaque, buffer: []u8) anyerror!usize {
            const ptr: *const Context = @alignCast(@ptrCast(context));
            return readFn(ptr.*, buffer);
        }
    };
}

pub fn GenericWriter(
    comptime Context: type,
    comptime WriteError: type,
    comptime writeFn: fn (context: Context, bytes: []const u8) WriteError!usize,
) type {
    return struct {
        context: Context,

        const Self = @This();
        pub const Error = WriteError;

        pub fn write(self: Self, bytes: []const u8) Error!usize {
            return writeFn(self.context, bytes);
        }

        pub fn writeAll(self: Self, bytes: []const u8) Error!void {
            try self.any().writeAll(bytes);
        }

        pub fn print(self: Self, comptime format: []const u8, args: anytype) Error!void {
            try self.any().print(format, args);
        }

        pub fn writeByte(self: Self, byte: u8) Error!void {
            return @errorCast(self.any().writeByte(byte));
        }

        pub inline fn any(self: *const Self) AnyWriter {
            return .{
                .context = @ptrCast(&self.context),
                .writeFn = typeErasedWriteFn,
            };
        }

        fn typeErasedWriteFn(context: *const anyopaque, bytes: []const u8) Error!usize {
            const ptr: *const Context = @alignCast(@ptrCast(context));
            return writeFn(ptr.*, bytes);
        }
    };
}

pub const Writer = GenericWriter;
pub const AnyWriter = @import("io/Writer.zig");

pub const AnyReader = @import("io/Reader.zig");
pub const Reader = GenericReader;

pub const FixedBufferStream = @import("io/fixed_buffer_stream.zig").FixedBufferStream;
pub const fixedBufferStream = @import("io/fixed_buffer_stream.zig").fixedBufferStream;

pub fn dummyWrite(_: void, data: []const u8) error{}!usize {
    return data.len;
}

pub const NullWriter = Writer(void, error{}, dummyWrite);
pub const null_writer: NullWriter = .{ .context = {} };

pub const countingWriter = @import("io/counting_writer.zig").countingWriter;
pub const CountingWriter = @import("io/counting_writer.zig").CountingWriter;
