const ft = @import("../ft.zig");

fn FixedBufferStream(comptime Buffer: type) type {
    return struct {
        buffer: Buffer,
        pos: usize = 0,

        pub const ReadError = error{};
        pub const WriteError = error{NoSpaceLeft};
        pub const SeekError = error{};
        pub const GetSeekPosError = error{};

        pub const Writer = ft.io.Writer(*Self, Self.WriteError, Self.write);

        const Self = @This();

        pub fn getEndPos(self: *Self) GetSeekPosError!u64 {
            return @intCast(self.buffer.len);
        }

        pub fn getPos(self: *Self) GetSeekPosError!u64 {
            return self.pos;
        }

        pub fn getWritten(self: Self) Buffer {
            return self.buffer[0..self.pos];
        }

        // pub fn read(self: *Self, dest: []u8) ReadError!usize {
        // 	unreachable; //todo
        // }

        // pub fn reader(self: *Self) Reader {
        // 	unreachable; //todo
        // }

        pub fn reset(self: *Self) void {
            self.pos = 0;
        }

        pub fn seekBy(self: *Self, amt: i64) SeekError!void {
            if (amt > 0) {
                if (amt +| self.pos > self.buffer.len) {
                    self.pos = self.buffer.len;
                } else {
                    self.pos += @as(usize, @intCast(amt));
                }
            } else {
                self.pos -|= @as(usize, @intCast(-amt));
            }
        }

        pub fn seekTo(self: *Self, pos: u64) SeekError!void {
            self.pos = pos;
        }

        // pub fn seekableStream(self: *Self) SeekableStream {
        // 	unreachable; //todo
        // }

        pub fn write(self: *Self, bytes: []const u8) WriteError!usize {
            var ret: usize = 0;
            for (bytes) |b| {
                if (self.pos == self.buffer.len)
                    break;
                self.buffer[self.pos] = b;
                self.pos += 1;
                ret += 1;
            }
            if (ret == 0)
                return WriteError.NoSpaceLeft;
            return ret;
        }

        pub fn writer(self: *Self) Writer {
            return Self.Writer{ .context = self };
        }
    };
}

pub fn fixedBufferStream(buffer: anytype) FixedBufferStream(Slice(@TypeOf(buffer))) {
    return .{ .buffer = buffer };
}

pub fn Slice(comptime T: type) type {
    switch (@typeInfo(T)) {
        .Pointer => |p| {
            var new_p = p;
            switch (p.size) {
                .Slice => {}, // ok
                .One => switch (@typeInfo(p.child)) {
                    .Array => |a| {
                        new_p.child = a.child;
                    },
                    else => @compileError("invalid type"),
                },
                else => @compileError("invalid type"),
            }
            new_p.size = .Slice;
            return @Type(.{ .Pointer = new_p });
        },
        else => @compileError("invalid type"),
    }
}
