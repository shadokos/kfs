const ft = @import("ft.zig");

pub const ParseIntError = error{ Overflow, InvalidCharacter };

pub fn parseInt(comptime T: type, buf: []const u8, _base: u8) ParseIntError!T {
	var base : u8 = _base;
    var index: usize = 0;

    if (buf.len <= index)
        return ParseIntError.InvalidCharacter;

    const is_neg: bool = buf[index] == '-';

    if (buf[index] == '-' or buf[index] == '+')
        index += 1;

    if (buf.len <= index)
        return ParseIntError.InvalidCharacter;

	if (base == 0 and buf[index] == '0' and buf.len > index + 1) {
		switch (buf[index + 1]) {
			'o','O' => {base = 8; index += 2;},
			'x','X' => {base = 16; index += 2;},
			'b','B' => {base = 2; index += 2;},
			else => {}
		}
		if (buf.len <= index)
			return ParseIntError.InvalidCharacter;
	}
	if (base == 0)
		base = 10;

    if (buf.len <= index or buf[index] == '_')
    	return ParseIntError.InvalidCharacter;

    const U = ft.meta.Int(@typeInfo(T).Int.signedness, @max(8, @typeInfo(T).Int.bits));
    var ret: U = 0;

    while (index < buf.len) : (index += 1) {
    	if (buf[index] == '_')
    		continue;
        var ov = @mulWithOverflow(ret, @as(U, @intCast(base)));
        if (ov[1] != 0) return ParseIntError.Overflow;

        if (is_neg) {
            ov = @subWithOverflow(ov[0], @as(U, @intCast(charToDigit(buf[index], base) catch return ParseIntError.InvalidCharacter)));
        } else {
            ov = @addWithOverflow(ov[0], @as(U, @intCast(charToDigit(buf[index], base) catch return ParseIntError.InvalidCharacter)));
        }
        if (ov[1] != 0) return ParseIntError.Overflow;

        ret = ov[0];
    }

    return @as(T, @intCast(ret));
}

test "parseInt" { // stolen from zig's ft lib
	const std = @import("std");
	const math = std.math;
    try std.testing.expect((try parseInt(i32, "-10", 10)) == -10);
    try std.testing.expect((try parseInt(i32, "+10", 10)) == 10);
    try std.testing.expect((try parseInt(u32, "+10", 10)) == 10);
    try std.testing.expectError(error.Overflow, parseInt(u32, "-10", 10));
    try std.testing.expectError(error.InvalidCharacter, parseInt(u32, " 10", 10));
    try std.testing.expectError(error.InvalidCharacter, parseInt(u32, "10 ", 10));
    try std.testing.expectError(error.InvalidCharacter, parseInt(u32, "_10_", 10));
    try std.testing.expectError(error.InvalidCharacter, parseInt(u32, "0x_10_", 10));
    try std.testing.expectError(error.InvalidCharacter, parseInt(u32, "0x10_", 10));
    try std.testing.expectError(error.InvalidCharacter, parseInt(u32, "0x_10", 10));
    try std.testing.expect((try parseInt(u8, "255", 10)) == 255);
    try std.testing.expectError(error.Overflow, parseInt(u8, "256", 10));

    // +0 and -0 should work for unsigned

    try std.testing.expect((try parseInt(u8, "-0", 10)) == 0);
    try std.testing.expect((try parseInt(u8, "+0", 10)) == 0);

    // ensure minInt is parsed correctly

    try std.testing.expect((try parseInt(i1, "-1", 10)) == math.minInt(i1));
    try std.testing.expect((try parseInt(i8, "-128", 10)) == math.minInt(i8));
    try std.testing.expect((try parseInt(i43, "-4398046511104", 10)) == math.minInt(i43));

    // empty string or bare +- is invalid

    try std.testing.expectError(error.InvalidCharacter, parseInt(u32, "", 10));
    try std.testing.expectError(error.InvalidCharacter, parseInt(i32, "", 10));
    try std.testing.expectError(error.InvalidCharacter, parseInt(u32, "+", 10));
    try std.testing.expectError(error.InvalidCharacter, parseInt(i32, "+", 10));
    try std.testing.expectError(error.InvalidCharacter, parseInt(u32, "-", 10));
    try std.testing.expectError(error.InvalidCharacter, parseInt(i32, "-", 10));

    // autodectect the base todo

    try std.testing.expect((try parseInt(i32, "111", 0)) == 111);
    try std.testing.expect((try parseInt(i32, "1_1_1", 0)) == 111);
    try std.testing.expect((try parseInt(i32, "1_1_1", 0)) == 111);
    try std.testing.expect((try parseInt(i32, "+0b111", 0)) == 7);
    try std.testing.expect((try parseInt(i32, "+0B111", 0)) == 7);
    try std.testing.expect((try parseInt(i32, "+0b1_11", 0)) == 7);
    try std.testing.expect((try parseInt(i32, "+0o111", 0)) == 73);
    try std.testing.expect((try parseInt(i32, "+0O111", 0)) == 73);
    try std.testing.expect((try parseInt(i32, "+0o11_1", 0)) == 73);
    try std.testing.expect((try parseInt(i32, "+0x111", 0)) == 273);
    try std.testing.expect((try parseInt(i32, "-0b111", 0)) == -7);
    try std.testing.expect((try parseInt(i32, "-0b11_1", 0)) == -7);
    try std.testing.expect((try parseInt(i32, "-0o111", 0)) == -73);
    try std.testing.expect((try parseInt(i32, "-0x111", 0)) == -273);
    try std.testing.expect((try parseInt(i32, "-0X111", 0)) == -273);
    try std.testing.expect((try parseInt(i32, "-0x1_11", 0)) == -273);

    // bare binary/octal/decimal prefix is invalid

    try std.testing.expectError(error.InvalidCharacter, parseInt(u32, "0b", 0));
    try std.testing.expectError(error.InvalidCharacter, parseInt(u32, "0o", 0));
    try std.testing.expectError(error.InvalidCharacter, parseInt(u32, "0x", 0));

    // edge cases which previously errored due to base overflowing T

    try std.testing.expectEqual(@as(i2, -2), try parseInt(i2, "-10", 2));
    try std.testing.expectEqual(@as(i4, -8), try parseInt(i4, "-10", 8));
    try std.testing.expectEqual(@as(i5, -16), try parseInt(i5, "-10", 16));
}

pub const BufPrintError = error{NoSpaceLeft};

pub fn bufPrint(buf: []u8, comptime fmt: []const u8, args: anytype) BufPrintError![]u8 {
	var stream = ft.io.fixedBufferStream(buf);
	try format(stream.writer(), fmt, args);
	return stream.getWritten();
}

pub fn charToDigit(c: u8, base: u8) error{InvalidCharacter}!u8 {
    const ret = switch (c) {
        '0'...'9' => c - '0',
        'a'...'z' => c - 'a' + 10,
        'A'...'Z' => c - 'A' + 10,
        else => return error.InvalidCharacter,
    };
    if (ret >= base)
        return error.InvalidCharacter;
    return ret;
}

pub fn digitToChar(digit: u8, case: Case) u8 {
	return switch (digit) {
		0...9 => '0' + @as(u8, digit),
		10...35 => (if (case == Case.upper) @as(u8, 'A') else @as(u8, 'a')) + @as(u8, digit - 10),
		else => ' '
	};
}

const Argument = union(enum) {
	index: u32,
	name: []const u8,
};
const Specifier = enum {
	lower_hexa,
	upper_hexa,
	string,
	float,
	decimal,
	binary,
	octal,
	ascii,
	utf,
	optional,
	err,
	address,
	any
};

pub const FormatOptions = struct {
	precision : ?usize = null,
	width : ?usize = null,
	alignment : enum {
		left,
		center,
		right,
	} = .right,
	fill : u8 = ' '
};

pub const Case = enum {
	lower,
	upper
};

fn accept(comptime set: ?[] const u8, comptime str: *[]const u8) !?u8
{
	comptime {if (str.*.len == 0)
		return error.UnexpectedChar;
	if (set) |set_value|
	{
		for (set_value) |e| {
			if (e == str.*[0]) {
				str.* = str.*[1..];
				return e;
			}
		}
	} else {
		const ret = str.*[0];
		str.* = str.*[1..];
		return ret;
	}
	return null;
	}
}

fn expect(comptime set: [] const u8, comptime str: *[]const u8) !u8
{
	comptime return try accept(set, str) orelse error.UnexpectedChar;
}

fn get_argument(comptime fmt: *[]const u8) !?Argument
{
	comptime {
		if (try accept("[", fmt)) |_|
		{
			const end = ft.mem.indexOfScalarPos(u8, fmt.*, 0, ']') orelse error.UnexpectedChar;
			comptime var ret = .{.name = fmt.*[0..end]};
			fmt.* = fmt.*[end..];
			_ = try expect("]", fmt);
			return ret;
		}
		else if (fmt.*.len > 0 and (fmt.*[0] >= '0' and fmt.*[0] <= '9'))
		{
			comptime var end = 0;
			while (end < fmt.*.len and (fmt.*[end] >= '0' and fmt.*[end] <= '9')) {end += 1;}
			const ret = Argument{.index = parseInt(u32, fmt.*[0..end], 10) catch @compileError("invalid index")};
			fmt.* = fmt.*[end..];
			return ret;
		}
	}
	return null;
}

fn get_int(comptime fmt: *[]const u8) ?usize {
	comptime var end = 0;
	while (end < fmt.*.len and (fmt.*[end] >= '0' and fmt.*[end] <= '9')) {end += 1;}
	if (end == 0)
		return null;
	const ret = parseInt(u32, fmt.*[0..end], 10) catch unreachable;
	fmt.* = fmt.*[end..];
	return ret;
}

fn get_specifier(comptime fmt: *[]const u8) !?Specifier {
	return switch (try accept("xXsedbocu?!*a", fmt) orelse {return null;}) {
		'x' => .lower_hexa,
		'X' => .upper_hexa,
		's' => .string,
		'e' => .float,
		'd' => .decimal,
		'b' => .binary,
		'o' => .octal,
		'c' => .ascii,
		'u' => .utf,
		'?' => .optional,
		'!' => .err,
		'*' => .address,
		'a' => {
			_ = try expect("n", fmt);
			_ = try expect("y", fmt);
			.any;
		},
		else => unreachable
	};
}


pub fn format(writer: anytype, comptime fmt: []const u8, args: anytype) !void {
    comptime var fmt_copy = fmt;
    comptime var current_arg = 0;

    inline while (fmt_copy.len > 0) {
        if (comptime accept("{", &fmt_copy) catch unreachable) |_| {
            if (comptime accept("{", &fmt_copy) catch {}) |c| {
                try writer.writeByte(c);
            } else {
				comptime var argument : ?Argument = try get_argument(&fmt_copy);
				if (argument == null)
				{
					current_arg += 1;
					argument = Argument{.index = current_arg - 1};
				}
				comptime var specifier : Specifier = try get_specifier(&fmt_copy) orelse Specifier.any;
				comptime var options = FormatOptions{}; // todo
				if (comptime accept(":", &fmt_copy) catch null) |_| {
					if (fmt_copy.len >= 2 and (fmt_copy[1] == '<' or fmt_copy[1] == '^' or fmt_copy[1] == '>'))
					{
						options.fill = (comptime accept(null, &fmt_copy) catch {}).?;
						options.alignment = switch ((comptime accept(null, &fmt_copy) catch {}).?) {
							'<' => .left,
							'^' => .center,
							'>' => .right,
							else => unreachable
						};
					}
					options.width = comptime get_int(&fmt_copy);
				}
				if (comptime accept(".", &fmt_copy) catch null) |_| {
					options.precision = get_int(&fmt_copy);
				}
				_ = comptime expect("}", &fmt_copy) catch @compileError("unexpected char");

				comptime var arg_pos = switch(argument.?) {
					.index => |n| n,
					.name => |n| ft.meta.fieldIndex(@TypeOf(args), n) orelse @compileError("bonjour")
				};

				const arg_object = @field(args, @typeInfo(@TypeOf(args)).Struct.fields[arg_pos].name);
				try formatObj(arg_object, specifier, options, writer);
            }
        } else if (comptime accept("}", &fmt_copy) catch unreachable) |_| {
            if (comptime accept("}", &fmt_copy) catch null) |c| {
				try writer.writeByte(c);
            } else {
            	@compileError("missing opening {");
            }
        } else if (comptime accept(null, &fmt_copy) catch unreachable) |c| {
			comptime var next = 0;
			comptime {
				while (next < fmt_copy.len and fmt_copy[next] != '{') {
					next += 1;
				}
			}
			try writer.writeByte(c);
			_ = try writer.write(fmt_copy[0..next]);
			fmt_copy = fmt_copy[next..];
        }
    }
}

pub fn formatObj(obj: anytype, comptime specifier : Specifier, comptime options: FormatOptions, writer: anytype) !void {
	switch (@typeInfo(@TypeOf(obj))) {
		.Bool => |_| {
			try formatBuf(if (obj) "true" else "false", options, writer);
		},
		.Int, .ComptimeInt =>  {
			switch(specifier) {
				.decimal => try formatInt(obj, 10, Case.lower, options, writer),
				.lower_hexa, .upper_hexa => try formatInt(obj, 16, if (specifier == .lower_hexa) Case.lower else Case.upper, options, writer),
				.octal => try formatInt(obj, 8, Case.lower, options, writer),
				.binary => try formatInt(obj, 2, Case.lower, options, writer),
				else => try formatInt(obj, 10, Case.lower, options, writer),
			}
		},
		.Pointer => |pointer| {
			switch (pointer.size) {
				.One => {
					switch (specifier) {
						.address => {
							_ = try writer.write(@typeName(pointer.child));
							try writer.writeByte('@');
							try formatInt(@intFromPtr(obj), 16, Case.lower, .{.width = @sizeOf(*u8) * 2, .alignment = .right, .fill = '0'}, writer);
						},
						else => {
							try formatObj(obj.*, specifier, options, writer);
						}
					}
				},
				.Many, .C, .Slice => {
					switch (specifier) {
						.string => {
							try formatBuf(obj, options, writer);
						},
						.address => {
							_ = try writer.write(@typeName(@TypeOf(obj)));
							try writer.writeByte('@');
							try formatInt(@intFromPtr(obj), 16, Case.lower, .{.width = @sizeOf(*u8) * 2, .alignment = .right, .fill = '0'}, writer);
						},
						else => {
							@compileError("invalid specifier: " ++ @tagName(specifier));
						}
					}
				},
			}
		},
		.Array => |_| {
			switch (specifier) {
				.string => {
					try formatBuf(obj[0..], options, writer);
				},
				else => {
					@compileError("invalid specifier");
				}
			}
		},
		// .Struct,
		// .ComptimeFloat,
		// .Float,
		.Optional, .Null => {
			if (obj) |value| {
				try formatObj(value, specifier, options, writer);
			} else {
				try formatBuf("null", options, writer);
			}
		},
		// .ErrorUnion,
		// .ErrorSet,
		.Enum => {
			_ = try writer.write(@typeName(@TypeOf(obj)));
			try writer.writeByte('.');
			try formatBuf(@tagName(obj), options, writer);
		},
		.EnumLiteral => {
			try writer.writeByte('.');
			try formatBuf(@tagName(obj), options, writer);
		},
		// .Union,
		// .Vector,
		else => {@compileError("can't format type " ++ @typeName(@TypeOf(obj)));}
	}
}

pub fn formatBuf(buf: []const u8, options: FormatOptions, writer: anytype) !void
{
	var padding = if (options.width) |w| if (buf.len < w) w - buf.len else null else null;
	var right_padding = if (padding) |p| switch (options.alignment) {
		.right => 0,
		.center => p / 2,
		.left => p,
	} else null;
	var left_padding = if (padding) |p| switch (options.alignment) {
		.right => p,
		.center => p / 2 + p % 2,
		.left => 0,
	} else null;

	if (left_padding) |p| for (0..p) |_|
		{_ = try writer.write(&[1]u8{options.fill});};

	_ = try writer.write(buf);

	if (right_padding) |p| for (0..p) |_|
		{_ = try writer.write(&[1]u8{options.fill});};
}

pub fn formatInt(value: anytype, base: u8, case: Case, options: FormatOptions, writer: anytype) !void
{
	var index : usize = 0;
	const Int = switch ( @typeInfo(@TypeOf(value))) {
		.ComptimeInt => |_| ft.math.IntFittingRange(value, value),
		.Int => |_| @TypeOf(value),
		else => unreachable // hopefully
	};
    const U = ft.meta.Int(.unsigned, @max(8, @typeInfo(Int).Int.bits));

	var buffer : [@typeInfo(U).Int.bits + 1]u8 = undefined;
	@memset(&buffer, 0);

	var value_cpy: U = 0;
	if (value < 0)
	{
		buffer[index] = '-';
		index += 1;
		value_cpy = @intCast(-value);
	} else {
		value_cpy = @intCast(value);
	}

	var tmp : U = value_cpy;
	while (tmp != 0) : (tmp = @divTrunc(tmp, @as(U, @intCast(base)))) {
		index += 1;
	}
	if (value == 0)
	{
		index = 1;
		buffer[0] = '0';
	}

	const end = index;
	tmp = value_cpy;
	while (tmp != 0) : (tmp = @divTrunc(tmp, @as(U, @intCast(base)))) {
		index -= 1;
		buffer[index] = digitToChar(@as(u8,@intCast(@mod(tmp, @as(U, @intCast(base))))), case);
	}
	return formatBuf(buffer[0..end], options, writer);
}