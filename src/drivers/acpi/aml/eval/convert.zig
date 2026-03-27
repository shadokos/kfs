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
