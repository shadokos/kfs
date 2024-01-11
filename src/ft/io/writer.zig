const ft = @import("../ft.zig");

pub fn Writer(
	comptime Context: type,
	comptime Error: type,
	comptime callback: fn(context: Context, bytes: []const u8) Error!usize,
) type {
	return struct {
		context: Context,

		const Self = @This();

		pub fn print(self: Self, comptime format: []const u8, args: anytype) Error!void {
			return ft.fmt.format(self, format, args);
		}

		pub fn write(self: Self, bytes: []const u8) Error!usize {
			return callback(self.context, bytes);
		}

		pub fn writeAll(self: Self, bytes: []const u8) Error!void {
			var offset: usize = 0;
			while (offset != bytes.len) {
				offset += try self.write(bytes[offset..]);
			}
		}

		pub fn writeByte(self: Self, byte: u8) Error!void {
			_ = try callback(self.context, &([1]u8{byte}));
		}
	};
}