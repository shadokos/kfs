const ft = @import("ft/ft.zig");
const Builtins = @import("shell/builtins.zig");
const token = @import("shell/token.zig");
const tty = @import("tty/tty.zig");
const utils = @import("shell/utils.zig");
const allocator = @import("memory.zig").physicalMemory.allocator();

const TokenizerError = token.TokenizerError;
const max_line_size: u16 = 1024;
var status_code: usize = 0;

pub const CmdError = error{ CommandNotFound, InvalidNumberOfArguments, InvalidParameter, OtherError };

pub fn Shell(comptime _builtins: anytype) type {
    return struct {
        const builtins = _builtins;
        const Self = @This();
        var err: bool = false;

        reader: ft.io.AnyReader = undefined,
        writer: tty.Tty.Writer = undefined,

        pub fn init(_reader: ft.io.AnyReader, _writer: tty.Tty.Writer) Self {
            const ret = Self{
                .reader = _reader,
                .writer = _writer,
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

        pub fn routine(self: *Self) void {
            utils.print_prompt(err);

            // Read a line from the reader
            var slice = self.reader.readUntilDelimiterAlloc(allocator, '\n', 4096) catch |e| {
                if (e == error.StreamTooLong) {
                    utils.print_error("Line is too long", .{});
                    _ = self.reader.skipUntilDelimiterOrEof('\n') catch {};
                }
                err = true;
                return;
            };
            defer allocator.free(slice);

            // Tokenize the line
            const args = token.tokenize(slice) catch |e| {
                switch (e) {
                    token.TokenizerError.InvalidQuote => utils.print_error("invalid quotes", .{}),
                    token.TokenizerError.MaxTokensReached => utils.print_error(
                        "too many tokens (max: {d})",
                        .{token.max_tokens},
                    ),
                }
                err = true;
                return;
            };
            if (args.len == 0) return;

            utils.ensure_newline();

            err = false;
            self.exec_cmd(args) catch |e| {
                err = true;
                switch (e) {
                    CmdError.CommandNotFound => utils.print_error("{s}: command not found", .{args[0]}),
                    CmdError.InvalidNumberOfArguments => utils.print_error("Invalid number of arguments", .{}),
                    CmdError.InvalidParameter => utils.print_error("Invalid parameter", .{}),
                    CmdError.OtherError => {}, // specific errors are handled by the command itself
                }
            };
        }
    };
}
