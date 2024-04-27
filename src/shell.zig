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

fn exec_cmd(args: [][]u8) CmdError!void {
    // Search for a builtin command by iterating over those defined in shell/builtins.zig
    inline for (@typeInfo(Builtins).Struct.decls) |decl| {
        if (ft.mem.eql(u8, decl.name, args[0])) {
            return @field(Builtins, decl.name)(args);
        }
    }
    return CmdError.CommandNotFound;
}

pub fn shell() u8 {
    var reader = tty.get_reader();
    tty.get_tty().config.c_lflag.ECHOCTL = true;

    var err: bool = false;

    while (true) {
        utils.print_prompt(err);

        // Read a line from the tty
        const slice = reader.readUntilDelimiterAlloc(allocator, '\n', 4096) catch |e| {
            if (e == error.StreamTooLong) {
                utils.print_error("Line is too long", .{});
                _ = reader.skipUntilDelimiterOrEof('\n') catch {};
            }
            err = true;
            continue;
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
            continue;
        };
        if (args.len == 0) continue;

        utils.ensure_newline();

        err = false;
        exec_cmd(args) catch |e| {
            err = true;
            switch (e) {
                CmdError.CommandNotFound => utils.print_error("{s}: command not found", .{args[0]}),
                CmdError.InvalidNumberOfArguments => utils.print_error("Invalid number of arguments", .{}),
                CmdError.InvalidParameter => utils.print_error("Invalid parameter", .{}),
                CmdError.OtherError => {}, // specific errors are handled by the command itself
            }
        };
    }
    return 0;
}
