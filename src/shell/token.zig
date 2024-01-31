const ft = @import("../ft/ft.zig");
const tty = @import("../tty/tty.zig");

pub const max_tokens = 32;

pub const Tokens = [max_tokens][]u8;
var tokens: Tokens = undefined;

pub const TokenizerError = error {
	InvalidQuote,
	MaxTokensReached,
};

fn _skip_and_fill_whitespaces(data: *[]u8, i: *usize) void {
	var start = i.*;

	for (data.*[i.*..data.*.len]) |*c| switch (c.*) {
		0, 9...13, 32 => i.* += 1,
		else => break,
	};
	@memset(data.*[start..i.*], 0);
}

pub fn tokenize(data: *[]u8) TokenizerError![][]u8 {
 	var quote: enum { none, single, double } = .none;
 	var quote_offset: usize = 0;
	var index: usize = 0;
	var offset: usize = 0;

	var i: usize = 0;
	while (i < data.*.len) {
		const c = &data.*[i];
 		switch (quote) {
			.none => switch (c.*) {
				0, 9...13, 32 => {
					c.* = 0;
					const slice = @constCast(data.*[offset..i]);

					_skip_and_fill_whitespaces(data, &i);
					offset = i;

					if (slice.len == 0 or slice[0] == 0) continue ;

					if (index == max_tokens) return TokenizerError.MaxTokensReached;
					tokens[index] = slice;
					index += 1;
				},
				'\'', '"' => {
					quote = if (c.* == '\'') .single else .double;
					quote_offset = i;
					i += 1;
				},
				else => {
					i += 1;
				}
			},
			.single, .double => if (
				(quote == .single and c.* == '\'') or
				(quote == .double and c.* == '"')
			) {
				quote = .none;
				ft.mem.copyForwards(u8, data.*[quote_offset..i - 1], data.*[quote_offset + 1..i]);
				ft.mem.copyForwards(u8, data.*[i - 1..data.*.len - 1], data.*[i + 1..data.*.len]);
				@memset(data.*[data.*.len - 2..data.*.len], 0);
				i -|= 1;
			} else {
				i += 1;
			}
		}
	}
	if (quote != .none) return TokenizerError.InvalidQuote;
	return tokens[0..index];
}