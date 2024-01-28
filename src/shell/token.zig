const ft = @import("../ft/ft.zig");
const tty = @import("../tty/tty.zig");

const max_tokens = 256;

pub const Tokens = struct {
	tokens: [max_tokens:null]?[:0]u8 = undefined,
	len: usize = 0,
};

pub const TokenError = error {
	InvalidQuote,
};

fn skip_whitespaces(data: *[]u8, i: *usize) usize {
	var skipped: usize = 0;
	while (i.* < data.*.len and ft.ascii.isWhitespace(data.*[i.*])) : (skipped += 1) {
		i.* += 1;
	}
	return skipped;
}

pub fn tokenize(data: *[]u8) TokenError!Tokens {
	var ret: Tokens = Tokens{};
	var quote: enum { none, single, double } = .none;

	var current_quote: struct {
		start: ?usize = null,
		end: ?usize = null,
	} = .{ };

	var i: usize = 0;
	var offset: usize = 0;
	while (i < data.*.len) : (i += 1) {
		const c = data.*[i];
		switch (quote) {
			.none => switch (c) {
				0, 9...13, 32  => {
					data.*[i] = 0;

					const slice : *const[:0]u8 = &data.*[offset..i:0];

					_ = skip_whitespaces(data, &i);
					offset = i + 1;

					if (slice.*.len == 0 or slice.*[0] == 0) continue;
                    ret.tokens[ret.len] = slice.*;
                    ret.len += 1;
				},
				'\'', '"' => {
					quote = if (c == '\'') .single else .double;
					current_quote = .{ .start = i, .end = null };
				},
				else => {},
			},
			.single, .double => if ((quote == .single and c == '\'') or (quote == .double and c == '"')) {
			 	quote = .none; current_quote.end = i;
				ft.mem.copyForwards(
					u8,
					data.*[current_quote.start.?..current_quote.end.?-1],
					data.*[current_quote.start.? + 1..current_quote.end.?]
				);
				ft.mem.copyForwards(
					u8,
					data.*[current_quote.end.? - 1..data.*.len-1],
					data.*[current_quote.end.? + 1..data.*.len]
				);
				for (data.*[data.*.len-2..data.*.len]) |*_c| _c.* = 0;
				i -|= 2;
				offset = if (ft.ascii.isWhitespace(data.*[i])) i + 1 else offset;
			},
		}
	}
	if (quote != .none) return TokenError.InvalidQuote;
	ret.tokens[ret.len] = null;
	return ret;
}