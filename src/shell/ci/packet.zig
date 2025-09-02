const std = @import("std");
const Shell = @import("shell.zig").Shell;

const allocator = @import("../../memory.zig").smallAlloc.allocator();

pub fn Packet(comptime T: type) type {
    return struct {
        const Self = @This();

        writer: std.io.AnyWriter,
        err: ?anyerror = null,
        type: enum { Error, Info, Success } = .Info,
        data: T = undefined,

        pub fn init(writer: std.io.AnyWriter) Self {
            return .{ .writer = writer };
        }

        pub fn send(self: *Self) void {
            if (self.err) |_| self.type = .Error;
            self.printValue(self.*);
            _ = self.writer.write("\n") catch {};
        }

        pub fn sendf(self: *Self, comptime fmt: []const u8, args: anytype) void {
            if (self.err) |_| self.type = .Error;
            var buffer: std.ArrayList(u8) = .empty;
            std.fmt.format(buffer.writer(allocator), fmt, args) catch {};
            self.data = buffer.items;
            defer buffer.deinit(allocator);
            self.printValue(self.*);
            _ = self.writer.write("\n") catch {};
        }

        // TODO: Refactor this part in to use std.fmt
        pub fn printValue(self: *Self, data: anytype) void {
            const type_info = @typeInfo(@TypeOf(data));
            switch (type_info) {
                .int, .comptime_int => {
                    self.writer.print("{d}", .{data}) catch {};
                },
                .pointer => switch (type_info.pointer.size) {
                    .slice => {
                        if (type_info.pointer.child == u8) {
                            _ = self.writer.print("\"{s}\"", .{data}) catch {};
                        } else {
                            _ = self.writer.write("[") catch {};
                            for (data, 0..) |value, i| {
                                self.printValue(value);
                                if (i + 1 < data.len) _ = self.writer.write(", ") catch {};
                            }
                            _ = self.writer.write("]") catch {};
                        }
                    },
                    else => {
                        self.writer.print("{*}", .{data}) catch {};
                    },
                },
                .@"struct" => {
                    var nb_fields: u8 = 0;
                    inline for (type_info.@"struct".fields) |_| nb_fields += 1;
                    _ = self.writer.write("{ ") catch {};
                    inline for (
                        type_info.@"struct".fields,
                        0..,
                    ) |field, i| if (!std.mem.eql(u8, field.name, "writer")) {
                        _ = self.writer.print("\"{s}\": ", .{field.name}) catch {};
                        self.printValue(@field(data, field.name));
                        self.writer.print("{s} ", .{if (i + 1 < nb_fields) "," else ""}) catch {};
                    };
                    _ = self.writer.write("}") catch {};
                },
                .optional => if (data) |value| {
                    self.printValue(value);
                } else {
                    self.writer.print("null", .{}) catch {};
                },
                .error_set => {
                    self.writer.print("\"{s}\"", .{@errorName(data)}) catch {};
                },
                .@"enum" => {
                    self.writer.print("\"{s}\"", .{@tagName(data)}) catch {};
                },
                .void => {
                    self.writer.print("null", .{}) catch {};
                },
                else => {
                    @compileError("unsupported type: " ++ @typeName(@TypeOf(data)));
                },
            }
        }
    };
}
