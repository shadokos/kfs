const ft = @import("../ft/ft.zig");
const tty = @import("../tty/tty.zig");

pub const max_tokens = 32;

pub const Tokens = [max_tokens][]u8;
var tokens: Tokens = undefined;

const Tokenizer = struct {
	quote: enum { none, single, double } = .none,
	quote_offset: usize = 0,
	index: usize = 0,
	offset: usize = 0,
};

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

pub fn _slice_token(data: *[]u8, tokenizer: *Tokenizer, i: *usize) (TokenizerError || error{EmptyToken})!void {
	const slice = @constCast(data.*[tokenizer.offset..i.*]);
	_skip_and_fill_whitespaces(data, i);
	tokenizer.offset = i.*;

	if (slice.len == 0) return error.EmptyToken;
	if (tokenizer.index == max_tokens) return error.MaxTokensReached;
	tokens[tokenizer.index] = slice;
    tokenizer.index += 1;
}

pub fn tokenize(data: *[]u8) TokenizerError![][]u8 {
	var tokenizer = Tokenizer{};

	var i: usize = 0;
	while (i < data.*.len) {
		const c = &data.*[i];
 		switch (tokenizer.quote) {
			.none => switch (c.*) {
				0, 9...13, 32 => {
					c.* = 0;
					_slice_token(data, &tokenizer, &i) catch |err| switch (err) {
						error.EmptyToken => continue,
						else => |e| return e,
					};
				},
				'\'', '"' => {
					tokenizer.quote = if (c.* == '\'') .single else .double;
					tokenizer.quote_offset = i;
					i += 1;
				},
				else => {
					i += 1;
				}
			},
			.single, .double => if (
				(tokenizer.quote == .single and c.* == '\'') or
				(tokenizer.quote == .double and c.* == '"')
			) {
				tokenizer.quote = .none;
				ft.mem.copyForwards(u8, data.*[tokenizer.quote_offset..i - 1], data.*[tokenizer.quote_offset + 1..i]);
				ft.mem.copyForwards(u8, data.*[i - 1..data.*.len - 1], data.*[i + 1..data.*.len]);
				@memset(data.*[data.*.len - 2..data.*.len], 0);
				i -|= 1;
			} else {
				i += 1;
			}
		}
	}
	if (tokenizer.quote != .none) return TokenizerError.InvalidQuote;
	_slice_token(data, &tokenizer, &i) catch |err| switch (err) {
		error.EmptyToken => {},
		else => |e| return e,
	};
	return tokens[0..tokenizer.index];
}