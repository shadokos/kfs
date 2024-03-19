const ft = @import("../ft/ft.zig");
const token = @import("token.zig");
const colors = @import("colors");
const allocator = @import("../memory.zig").physicalMemory.allocator();

pub const CmdError = error{ CommandNotFound, InvalidNumberOfArguments, InvalidParameter, OtherError };
pub const Config = struct {
    colors: bool = true,
};

const max_line_size: u16 = 1024;

pub fn Shell(comptime _builtins: anytype) type {
    return struct {
        const builtins = _builtins;
        const Self = @This();

        const Hook: type = ?*const fn (*Self) void;
        const ErrorHook: type = ?*const fn (*Self, err: anyerror) void;

        const Hooks: type = struct {
            pre_process: Hook = null,
            post_process: Hook = null,
            pre_cmd: Hook = null,
            on_error: ErrorHook = null,
        };

        config: Config = Config{},
        err: bool = false,
        reader: ft.io.AnyReader = undefined,
        writer: ft.io.AnyWriter = undefined,
        hooks: Hooks = Hooks{},

        pub fn init(
            reader: ft.io.AnyReader,
            writer: ft.io.AnyWriter,
            config: Config,
            hooks: struct {
                pre_process: ?*const anyopaque = null,
                post_process: ?*const anyopaque = null,
                pre_cmd: ?*const anyopaque = null,
                on_error: ?*const anyopaque = null,
            },
        ) Self {
            const ret = Self{
                .reader = reader,
                .writer = writer,
                .config = config,
                .hooks = .{
                    .pre_process = if (hooks.pre_process) |h| @alignCast(@ptrCast(h)) else null,
                    .post_process = if (hooks.post_process) |h| @alignCast(@ptrCast(h)) else null,
                    .pre_cmd = if (hooks.pre_cmd) |h| @alignCast(@ptrCast(h)) else null,
                    .on_error = if (hooks.on_error) |h| @alignCast(@ptrCast(h)) else null,
                },
            };
            return ret;
        }

        fn exec_cmd(self: *Self, args: [][]u8) CmdError!void {
            // Search for a builtin command by iterating over those defined in shell/builtins.zig
            inline for (@typeInfo(builtins).Struct.decls) |decl| {
                if (ft.mem.eql(u8, decl.name, args[0])) {
                    return @field(builtins, decl.name)(self, args);
                }
            }
            return CmdError.CommandNotFound;
        }

        pub fn process_line(self: *Self) void {
            if (self.hooks.pre_process) |hook| hook(self);

            // Read a line from the reader
            var slice = self.reader.readUntilDelimiterAlloc(allocator, '\n', 4096) catch |e| {
                self.err = true;
                if (self.hooks.on_error) |hook| hook(self, e);
                if (e == error.StreamTooLong) {
                    self.print_error("Line is too long", .{});
                    _ = self.reader.skipUntilDelimiterOrEof('\n') catch {};
                }
                return;
            };
            defer allocator.free(slice);

            // Tokenize the line
            const args = token.tokenize(slice) catch |e| {
                self.err = true;
                if (self.hooks.on_error) |hook| hook(self, e);
                switch (e) {
                    error.InvalidQuote => self.print_error("invalid quotes", .{}),
                    error.MaxTokensReached => self.print_error(
                        "too many tokens (max: {d})",
                        .{token.max_tokens},
                    ),
                }
                return;
            };
            if (args.len == 0) return;

            if (self.hooks.pre_cmd) |hook| hook(self);

            self.err = false;
            self.exec_cmd(args) catch |e| {
                self.err = true;
                if (self.hooks.on_error) |hook| hook(self, e);
                switch (e) {
                    CmdError.CommandNotFound => self.print_error("{s}: command not found", .{args[0]}),
                    CmdError.InvalidNumberOfArguments => self.print_error("Invalid number of arguments", .{}),
                    CmdError.InvalidParameter => self.print_error("Invalid parameter", .{}),
                    CmdError.OtherError => {}, // specific errors are handled by the command itself
                }
            };
            if (self.hooks.post_process) |hook| hook(self);
        }

        pub fn print(self: *Self, comptime fmt: []const u8, args: anytype) void {
            self.writer.print(fmt, args) catch {};
        }

        pub fn print_error(self: *Self, comptime fmt: []const u8, args: anytype) void {
            const red = if (self.config.colors) colors.red else "";
            const reset = if (self.config.colors) colors.reset else "";
            self.writer.print("{s}Error{s}: " ++ fmt ++ "\n", .{ red, reset } ++ args) catch {};
        }

        pub fn strerror(_: *Self, err: anyerror) []const u8 {
            switch (err) {
                error.StreamTooLong => return "Stream too long",
                error.CommandNotFound => return "Command not found",
                error.InvalidNumberOfArguments => return "Invalid number of arguments",
                error.InvalidParameter => return "Invalid parameter",
                error.InvalidQuote => return "Invalid quote",
                error.MaxTokensReached => return "Max tokens reached",
                else => return "Unknown error",
            }
        }
    };
}
