const ft = @import("../ft.zig");

pub fn Reader(
	comptime Context: type,
	comptime ReadError: type,
	comptime readFn: fn (Context, []u8) ReadError!usize
) type {
	return struct {
		context: Context,

		const Self = @This();

		const Error = ReadError;

		pub fn read(self: Self, bytes: []u8) Error!usize {
			return readFn(self.context, bytes);
		}

		pub fn readAll(self: Self, bytes: []u8) Error!void {
			var offset: usize = 0;
			while (offset != bytes.len) {
				offset += try self.read(bytes[offset..]);
			}
		}

		pub fn readByte(self: Self, byte: u8) Error!void {
			_ = try readFn(self.context, &byte);
		}
	};
}