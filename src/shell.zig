const ft = @import("ft/ft.zig");
const Builtins = @import("shell/builtins.zig");
const token = @import("shell/token.zig");
const tty = @import("tty/tty.zig");
const utils = @import("shell/utils.zig");

const TokenizerError = token.TokenizerError;
const max_line_size: u16 = 1024;
var status_code: usize = 0;

pub fn shell() u8 {
	tty.get_tty().config.c_lflag.ECHOCTL = true;

	while (true) {
		utils.print_prompt(status_code);
		status_code = 0;

		// Read a line from the tty
		var data: [max_line_size]u8 = undefined;
		const data_len: usize = tty.get_reader().read(&data) catch return 1;

		var line: *const[]u8 = &data[0..data_len + 1];
		line.*[data_len] = 0;

		// Tokenize the line
		const args = token.tokenize(@constCast(line)) catch |err| {
			switch (err) {
				token.TokenizerError.InvalidQuote =>
					utils.print_error("invalid quotes", .{}),
				token.TokenizerError.MaxTokensReached =>
					utils.print_error("too many tokens (max: {d})", .{token.max_tokens}),
			}
			status_code = 2;
			continue ;
		};
		if (args.len == 0) continue ;

		utils.ensure_newline();

		// Search for a builtin command by iterating over those defined in shell/builtins.zig
		inline for (@typeInfo(Builtins).Struct.decls) |decl| {
			if (ft.mem.eql(u8, decl.name, args[0])) {
				status_code = @field(Builtins, decl.name)(args);
				break ; // break the for loop, the builtin was found
			}
			else status_code = 1;
		}
		if (status_code == 1)
			utils.print_error("{s}: command not found", .{args[0]});
	}
	return 0;
}