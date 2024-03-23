const ft = @import("../../ft/ft.zig");
const Shell = @import("shell.zig").Shell;

pub fn Packet(comptime T: type) type {
    return struct {
        const Self = @This();

        writer: ft.io.AnyWriter,
        err: ?anyerror = null,
        type: enum { Error, Info, Success } = .Info,
        data: T = undefined,

        pub fn init(writer: ft.io.AnyWriter) Self {
            return .{ .writer = writer };
        }

        pub fn send(self: *Self) void {
            if (self.err) |_| self.type = .Error;
            printValue(self, self.*);
            _ = self.writer.write("\n") catch {};
        }

        pub fn sendf(self: *Self, comptime fmt: []const u8, args: anytype) void {
            if (self.err) |_| self.type = .Error;
            self.writer.print("{{ \"err\": ", .{}) catch {};
            self.printValue(self.err);
            self.writer.print(", \"type\": ", .{}) catch {};
            self.printValue(self.type);
            self.writer.print(", \"data\": \"" ++ fmt ++ "\" }\n", args) catch {};
        }

        // TODO: Maybe implements this part in ft.fmt ??
        // TODO: Maybe not this code actually, but a way to print a struct
        pub fn printValue(self: *Self, data: anytype) void {
            const type_info = @typeInfo(@TypeOf(data));
            switch (type_info) {
                .Int, .ComptimeInt => {
                    self.writer.print("{d}", .{data}) catch {};
                },
                .Pointer => switch (type_info.Pointer.size) {
                    .Slice => {
                        if (type_info.Pointer.child == u8) {
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
                .Struct => {
                    var nb_fields: u8 = 0;
                    inline for (type_info.Struct.fields) |_| nb_fields += 1;
                    _ = self.writer.write("{ ") catch {};
                    inline for (type_info.Struct.fields, 0..) |field, i| if (!ft.mem.eql(u8, field.name, "writer")) {
                        _ = self.writer.print("\"{s}\": ", .{field.name}) catch {};
                        self.printValue(@field(data, field.name));
                        self.writer.print("{s} ", .{if (i + 1 < nb_fields) "," else ""}) catch {};
                    };
                    _ = self.writer.write("}") catch {};
                },
                .Optional => if (data) |value| {
                    self.printValue(value);
                } else {
                    self.writer.print("null", .{}) catch {};
                },
                .ErrorSet => {
                    self.writer.print("\"{s}\"", .{@errorName(data)}) catch {};
                },
                .Enum => {
                    self.writer.print("\"{s}\"", .{@tagName(data)}) catch {};
                },
                .Void => {
                    self.writer.print("null", .{}) catch {};
                },
                else => {
                    @compileLog(@typeInfo(@TypeOf(data)));
                },
            }
        }
    };
}
