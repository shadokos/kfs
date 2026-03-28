/// AML type conversion opcodes (ACPI 6.4 §20.2.5.4).
///
/// DefToInteger       := ToIntegerOp Operand Target       (§20.2.5.4, 0x99)
/// DefToBuffer        := ToBufferOp Operand Target        (§20.2.5.4, 0x96)
/// DefToHexString     := ToHexStringOp Operand Target     (§20.2.5.4, 0x98)
/// DefToDecimalString := ToDecimalStringOp Operand Target (§20.2.5.4, 0x97)
/// DefFromBCD         := FromBCDOp BCDValue Target        (§20.2.5.4, ExtOpPrefix 0x28)
/// DefToBCD           := ToBCDOp Operand Target           (§20.2.5.4, ExtOpPrefix 0x29)
const objects = @import("../objects.zig");
const integer = @import("integer.zig");
const store = @import("store.zig");
const osl = @import("../../os_layer.zig");

const Object = objects.Object;
const Error = @import("executor.zig").Error;
const EvalContext = @import("executor.zig").EvalContext;

fn eval_operand(ectx: *EvalContext) Error!Object {
    return @import("operand.zig").eval_operand(ectx);
}

/// DefToInteger (§20.2.5.4). Operand Target.
pub fn eval_to_integer(ectx: *EvalContext) Error!Object {
    const val = integer.to_int(try eval_operand(ectx));
    const result: Object = .{ .integer = integer.mask32(val) };
    try store.write_target(ectx, result);
    return result;
}

/// DefToBuffer (§19.6.136, opcode 0x96). Operand Target.
/// Integer → 4-byte little-endian buffer (32-bit mode per §19.3.5.7 Table 19.7).
/// String  → buffer of ASCII bytes including NUL terminator.
/// Buffer  → no conversion.
pub fn eval_to_buffer(ectx: *EvalContext) Error!Object {
    const obj = try eval_operand(ectx);
    const result: Object = switch (obj) {
        .uninitialized, .integer => blk: {
            const raw: u64 = if (obj == .integer) obj.integer else 0;
            const buf = osl.kmalloc(u8, 4) orelse return Error.out_of_nodes;
            const val: u32 = @truncate(raw);
            buf[0] = @truncate(val);
            buf[1] = @truncate(val >> 8);
            buf[2] = @truncate(val >> 16);
            buf[3] = @truncate(val >> 24);
            break :blk .{ .buffer = .{ .data = buf[0..4] } };
        },
        .string => |s| blk: {
            // Include NUL terminator per spec
            const len = s.len + 1;
            const buf = osl.kmalloc(u8, len) orelse return Error.out_of_nodes;
            @memcpy(buf[0..s.len], s);
            buf[s.len] = 0;
            break :blk .{ .buffer = .{ .data = buf[0..len] } };
        },
        .buffer => obj,
        else => obj,
    };
    try store.write_target(ectx, result);
    return result;
}

/// DefToHexString (§19.6.138, opcode 0x98). Operand Target.
/// Integer → 8-char hex string (32-bit mode, e.g. "0000ABCD") per §19.3.5.7 Table 19.7.
/// Buffer  → comma-separated hex pairs (e.g. "AB,CD,EF").
/// String  → no conversion.
pub fn eval_to_hex_string(ectx: *EvalContext) Error!Object {
    const obj = try eval_operand(ectx);
    const result: Object = switch (obj) {
        .uninitialized, .integer => blk: {
            // 8 hex chars for 32-bit integer
            const buf = osl.kmalloc(u8, 8) orelse return Error.out_of_nodes;
            const raw: u64 = if (obj == .integer) obj.integer else 0;
            const val: u32 = @truncate(raw);
            const hex = "0123456789ABCDEF";
            comptime var i: usize = 0;
            inline while (i < 8) : (i += 1) {
                buf[i] = hex[@as(u4, @truncate(val >> @intCast((7 - i) * 4)))];
            }
            break :blk .{ .string = buf[0..8] };
        },
        .buffer => |b| blk: {
            if (b.data.len == 0) {
                break :blk .{ .string = "" };
            }
            // "XX,XX,XX" = 3*n - 1 chars
            const len = b.data.len * 3 - 1;
            const buf = osl.kmalloc(u8, len) orelse return Error.out_of_nodes;
            const hex = "0123456789ABCDEF";
            for (b.data, 0..) |byte, idx| {
                const pos = idx * 3;
                buf[pos] = hex[@as(u4, @truncate(byte >> 4))];
                buf[pos + 1] = hex[@as(u4, @truncate(byte))];
                if (idx + 1 < b.data.len) buf[pos + 2] = ',';
            }
            break :blk .{ .string = buf[0..len] };
        },
        .string => obj,
        else => obj,
    };
    try store.write_target(ectx, result);
    return result;
}

/// DefToDecimalString (§19.6.137, opcode 0x97). Operand Target.
/// Integer → decimal ASCII string (e.g. 255 → "255").
/// Buffer  → comma-separated decimal byte values (e.g. {0xFF,0x01} → "255,1").
/// String  → no conversion.
pub fn eval_to_decimal_string(ectx: *EvalContext) Error!Object {
    const obj = try eval_operand(ectx);
    const result: Object = switch (obj) {
        .uninitialized, .integer => blk: {
            const raw: u64 = if (obj == .integer) obj.integer else 0;
            const val: u32 = @truncate(raw);
            // Max u32 decimal is "4294967295" (10 chars)
            var tmp: [10]u8 = undefined;
            var len: usize = 0;
            var n = val;
            if (n == 0) {
                tmp[0] = '0';
                len = 1;
            } else {
                while (n > 0) : (len += 1) {
                    tmp[len] = @truncate('0' + (n % 10));
                    n /= 10;
                }
                // Reverse in place
                var lo: usize = 0;
                var hi: usize = len - 1;
                while (lo < hi) {
                    const t = tmp[lo];
                    tmp[lo] = tmp[hi];
                    tmp[hi] = t;
                    lo += 1;
                    hi -= 1;
                }
            }
            const buf = osl.kmalloc(u8, len) orelse return Error.out_of_nodes;
            @memcpy(buf[0..len], tmp[0..len]);
            break :blk .{ .string = buf[0..len] };
        },
        .buffer => |b| blk: {
            if (b.data.len == 0) {
                break :blk .{ .string = "" };
            }
            // Max per byte: "255" (3 chars) + comma separator
            const max_len = b.data.len * 4;
            const buf = osl.kmalloc(u8, max_len) orelse return Error.out_of_nodes;
            var pos: usize = 0;
            for (b.data, 0..) |byte, idx| {
                if (idx > 0) {
                    buf[pos] = ',';
                    pos += 1;
                }
                // Write decimal value of byte
                if (byte >= 100) {
                    buf[pos] = @truncate('0' + byte / 100);
                    pos += 1;
                }
                if (byte >= 10) {
                    buf[pos] = @truncate('0' + (byte / 10) % 10);
                    pos += 1;
                }
                buf[pos] = @truncate('0' + byte % 10);
                pos += 1;
            }
            break :blk .{ .string = buf[0..pos] };
        },
        .string => obj,
        else => obj,
    };
    try store.write_target(ectx, result);
    return result;
}

/// DefConcat := ConcatOp Data1 Data2 Target (§19.6.12).
/// Type of Data1 determines result type:
///   Integer + any → 8-byte buffer (both as 4-byte LE).
///   String  + any → concatenated string (Data2 converted to string).
///   Buffer  + any → concatenated buffer (Data2 converted to buffer).
pub fn eval_concat(ectx: *EvalContext) Error!Object {
    const a = try eval_operand(ectx);
    const b = try eval_operand(ectx);

    const result: Object = switch (a) {
        .integer => blk: {
            const a_val: u32 = @truncate(integer.to_int(a));
            const b_val: u32 = @truncate(integer.to_int(b));
            const buf = osl.kmalloc(u8, 8) orelse return Error.out_of_nodes;
            buf[0] = @truncate(a_val);
            buf[1] = @truncate(a_val >> 8);
            buf[2] = @truncate(a_val >> 16);
            buf[3] = @truncate(a_val >> 24);
            buf[4] = @truncate(b_val);
            buf[5] = @truncate(b_val >> 8);
            buf[6] = @truncate(b_val >> 16);
            buf[7] = @truncate(b_val >> 24);
            break :blk .{ .buffer = .{ .data = buf[0..8] } };
        },
        .string => |s1| blk: {
            const s2: []const u8 = switch (b) {
                .string => |s| s,
                .integer => |v| i2s: {
                    var tmp: [10]u8 = undefined;
                    const len = fmt_u32(&tmp, @truncate(v));
                    const heap = osl.kmalloc(u8, len) orelse break :i2s "";
                    @memcpy(heap[0..len], tmp[0..len]);
                    break :i2s heap[0..len];
                },
                .buffer => |b2| b2.data,
                else => "",
            };
            const total = s1.len + s2.len;
            if (total == 0) break :blk .{ .string = "" };
            const buf = osl.kmalloc(u8, total) orelse return Error.out_of_nodes;
            if (s1.len > 0) @memcpy(buf[0..s1.len], s1);
            if (s2.len > 0) @memcpy(buf[s1.len..total], s2);
            break :blk .{ .string = buf[0..total] };
        },
        .buffer => |b1| blk: {
            const b2_data: []const u8 = switch (b) {
                .buffer => |b2| b2.data,
                .integer => |v| i2b: {
                    const heap = osl.kmalloc(u8, 4) orelse break :i2b &[_]u8{};
                    const val: u32 = @truncate(v);
                    heap[0] = @truncate(val);
                    heap[1] = @truncate(val >> 8);
                    heap[2] = @truncate(val >> 16);
                    heap[3] = @truncate(val >> 24);
                    break :i2b heap[0..4];
                },
                .string => |s| s,
                else => &[_]u8{},
            };
            const total = b1.data.len + b2_data.len;
            if (total == 0) break :blk .{ .buffer = .{ .data = &.{} } };
            const buf = osl.kmalloc(u8, total) orelse return Error.out_of_nodes;
            if (b1.data.len > 0) @memcpy(buf[0..b1.data.len], b1.data);
            if (b2_data.len > 0) @memcpy(buf[b1.data.len..total], b2_data);
            break :blk .{ .buffer = .{ .data = buf[0..total] } };
        },
        else => a,
    };
    try store.write_target(ectx, result);
    return result;
}

/// DefConcatRes := ConcatResOp BufData BufData Target (§19.6.13).
/// Concatenates two resource template buffers, stripping the End Tag
/// (0x79 + checksum byte) from the first before joining.
pub fn eval_concat_res(ectx: *EvalContext) Error!Object {
    const a = try eval_operand(ectx);
    const b = try eval_operand(ectx);

    const a_data: []const u8 = if (a == .buffer) a.buffer.data else &[_]u8{};
    const b_data: []const u8 = if (b == .buffer) b.buffer.data else &[_]u8{};

    // Strip End Tag (0x79 + 1 checksum byte) from first buffer
    var a_len = a_data.len;
    if (a_len >= 2 and a_data[a_len - 2] == 0x79) a_len -= 2;

    const total = a_len + b_data.len;
    if (total == 0) {
        const result: Object = .{ .buffer = .{ .data = &.{} } };
        try store.write_target(ectx, result);
        return result;
    }
    const buf = osl.kmalloc(u8, total) orelse return Error.out_of_nodes;
    if (a_len > 0) @memcpy(buf[0..a_len], a_data[0..a_len]);
    if (b_data.len > 0) @memcpy(buf[a_len..total], b_data);

    const result: Object = .{ .buffer = .{ .data = buf[0..total] } };
    try store.write_target(ectx, result);
    return result;
}

/// DefMid := MidOp MidObj TermArg TermArg Target (§19.6.85).
/// Extracts a substring or sub-buffer starting at Index for Length bytes/chars.
pub fn eval_mid(ectx: *EvalContext) Error!Object {
    const source = try eval_operand(ectx);
    const index = @as(usize, @intCast(integer.to_int(try eval_operand(ectx))));
    const length = @as(usize, @intCast(integer.to_int(try eval_operand(ectx))));

    const result: Object = switch (source) {
        .string => |s| blk: {
            if (index >= s.len) break :blk .{ .string = "" };
            const actual_len = @min(length, s.len - index);
            if (actual_len == 0) break :blk .{ .string = "" };
            const buf = osl.kmalloc(u8, actual_len) orelse return Error.out_of_nodes;
            @memcpy(buf[0..actual_len], s[index..][0..actual_len]);
            break :blk .{ .string = buf[0..actual_len] };
        },
        .buffer => |b| blk: {
            if (index >= b.data.len) break :blk .{ .buffer = .{ .data = &.{} } };
            const actual_len = @min(length, b.data.len - index);
            if (actual_len == 0) break :blk .{ .buffer = .{ .data = &.{} } };
            const buf = osl.kmalloc(u8, actual_len) orelse return Error.out_of_nodes;
            @memcpy(buf[0..actual_len], b.data[index..][0..actual_len]);
            break :blk .{ .buffer = .{ .data = buf[0..actual_len] } };
        },
        else => source,
    };
    try store.write_target(ectx, result);
    return result;
}

/// DefToString := ToStringOp TermArg LengthArg Target (§19.6.141).
/// Converts a Buffer to a String, up to LengthArg bytes. Null bytes terminate.
pub fn eval_to_string(ectx: *EvalContext) Error!Object {
    const source = try eval_operand(ectx);
    const length_arg = integer.to_int(try eval_operand(ectx));

    const result: Object = switch (source) {
        .buffer => |b| blk: {
            const max_len: usize = if (length_arg >= 0xFFFFFFFF)
                b.data.len
            else
                @min(@as(usize, @intCast(length_arg)), b.data.len);
            // Stop at null byte
            var actual_len: usize = 0;
            while (actual_len < max_len and b.data[actual_len] != 0) : (actual_len += 1) {}
            if (actual_len == 0) break :blk .{ .string = "" };
            const buf = osl.kmalloc(u8, actual_len) orelse return Error.out_of_nodes;
            @memcpy(buf[0..actual_len], b.data[0..actual_len]);
            break :blk .{ .string = buf[0..actual_len] };
        },
        .string => source,
        else => source,
    };
    try store.write_target(ectx, result);
    return result;
}

/// Format a u32 as a decimal string into buf. Returns the number of chars written.
fn fmt_u32(buf: *[10]u8, val: u32) usize {
    if (val == 0) {
        buf[0] = '0';
        return 1;
    }
    var n = val;
    var len: usize = 0;
    while (n > 0) : (len += 1) {
        buf[len] = @truncate('0' + (n % 10));
        n /= 10;
    }
    var lo: usize = 0;
    var hi: usize = len - 1;
    while (lo < hi) {
        const t = buf[lo];
        buf[lo] = buf[hi];
        buf[hi] = t;
        lo += 1;
        hi -= 1;
    }
    return len;
}

/// DefFromBCD (§20.2.5.4, ExtOpPrefix 0x28). BCDValue Target.
pub fn eval_from_bcd(ectx: *EvalContext) Error!Object {
    const bcd = integer.to_int(try eval_operand(ectx));
    var result: u64 = 0;
    var multiplier: u64 = 1;
    var val = bcd;
    while (val > 0) {
        result += (val & 0xF) * multiplier;
        val >>= 4;
        multiplier *= 10;
    }
    const obj: Object = .{ .integer = integer.mask32(result) };
    try store.write_target(ectx, obj);
    return obj;
}

/// DefToBCD (§20.2.5.4, ExtOpPrefix 0x29). Operand Target.
pub fn eval_to_bcd(ectx: *EvalContext) Error!Object {
    var val = integer.to_int(try eval_operand(ectx));
    var result: u64 = 0;
    var shift: u6 = 0;
    while (val > 0 and shift < 64) {
        result |= (val % 10) << shift;
        val /= 10;
        shift += 4;
    }
    const obj: Object = .{ .integer = integer.mask32(result) };
    try store.write_target(ectx, obj);
    return obj;
}
