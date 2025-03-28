const ft = @import("ft");
const Mutex = @import("../task/semaphore.zig").Mutex;

/// this class wrap a Writer and provide bufferization
pub fn BufferWriter(
    comptime Context: type,
    comptime Error: type,
    comptime callback: fn (context: Context, bytes: []const u8) Error!usize,
    comptime size: comptime_int,
) type {
    if (size <= 0)
        @compileError("buffer writer size must be greater than 0");
    return struct {
        context: Context,
        buffer: [size]u8 = undefined,
        index: usize = 0,
        lock: Mutex = Mutex{},

        const Self = @This();

        pub fn print(self: *Self, comptime format: []const u8, args: anytype) Error!void {
            self.lock.acquire();
            defer self.lock.release();

            return ft.fmt.format(self, format, args);
        }

        pub fn internal_flush(self: *Self) Error!void {
            _ = try callback(self.context, self.buffer[0..self.index]);
            self.index = 0;
        }

        pub fn flush(self: *Self) Error!void {
            self.lock.acquire();
            defer self.lock.release();

            try self.internal_flush();
        }

        pub fn write(self: *Self, bytes: []const u8) Error!usize {
            if (bytes.len +| self.index > self.buffer.len) {
                try self.internal_flush();
                return callback(self.context, bytes);
            } else {
                for (bytes) |b| {
                    self.buffer[self.index] = b;
                    self.index += 1;
                    if (b == '\n')
                        try self.internal_flush();
                }
                return bytes.len;
            }
        }

        pub fn writeAll(self: *Self, bytes: []const u8) Error!void {
            self.lock.acquire();
            defer self.lock.release();

            var offset: usize = 0;
            while (offset != bytes.len) {
                offset += try self.write(bytes[offset..]);
            }
        }

        pub fn writeByte(self: *Self, byte: u8) Error!void {
            self.lock.acquire();
            defer self.lock.release();

            _ = try self.write(&([1]u8{byte}));
        }
    };
}
