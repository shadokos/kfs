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

pub const Writer = @import("io/writer.zig").Writer;

pub const AnyReader = @import("io/Reader.zig");
pub const Reader = GenericReader;

pub const FixedBufferStream = @import("io/fixed_buffer_stream.zig").FixedBufferStream;
pub const fixedBufferStream = @import("io/fixed_buffer_stream.zig").fixedBufferStream;
