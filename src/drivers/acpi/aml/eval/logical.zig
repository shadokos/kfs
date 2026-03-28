/// AML logical expression opcodes (ACPI 6.4 §20.2.5.4).
///
/// All comparison ops: Def<Op> := <OpByte> Operand Operand
/// Logical boolean ops: DefLAnd/DefLOr := <OpByte> Operand Operand
/// Logical negation:    DefLNot := LnotOp Operand
///
/// Compound forms (decoded as two-byte sequences, §20.2.5.4):
///   DefLGreaterEqual := LnotOp LlessOp    (i.e. !(a < b))
///   DefLLessEqual    := LnotOp LgreaterOp (i.e. !(a > b))
///   DefLNotEqual     := LnotOp LequalOp   (i.e. !(a == b))
///
/// Comparison type coercion (§19.6.72, §19.3.5.7):
///   Only Integer, String, and Buffer are comparable. If operands differ in
///   type, the second is converted to the type of the first:
///     Integer: numeric comparison
///     String:  lexicographic byte-by-byte (§19.6.72)
///     Buffer:  lexicographic byte-by-byte, shorter < longer if prefix matches
///
/// All return Ones (integer 0xFFFFFFFF for rev 1) for true, Zero for false.
/// We follow the POC convention of returning 1/0 for clarity (both are
/// nonzero, so they work the same in boolean contexts).
const std = @import("std");
const objects = @import("../objects.zig");
const integer = @import("integer.zig");

const Object = objects.Object;
const Error = @import("executor.zig").Error;
const EvalContext = @import("executor.zig").EvalContext;

const to_int = integer.to_int;

fn eval_operand(ectx: *EvalContext) Error!Object {
    return @import("operand.zig").eval_operand(ectx);
}

inline fn bool_obj(cond: bool) Object {
    return .{ .integer = if (cond) @as(u64, 1) else 0 };
}

// -- Type-aware comparison (§19.6.72, §19.3.5.7) ----------------------------
//
// The first operand's type determines the comparison mode.
// The second operand is coerced to match.

/// Compare two AML objects per §19.6.72: dispatch on the first operand's type.
fn compare(a: Object, b: Object) std.math.Order {
    return switch (a) {
        .string => |sa| compare_as_string(sa, b),
        .buffer => |ba| compare_as_buffer(ba.data, b),
        else => std.math.order(to_int(a), to_int(b)),
    };
}

/// String comparison: coerce second operand to string, then lexicographic.
/// Coercion rules (§19.3.5.7 Table 19.8):
///   Integer -> decimal string, Buffer -> raw bytes treated as string.
fn compare_as_string(sa: []const u8, b: Object) std.math.Order {
    switch (b) {
        .string => |sb| return std.mem.order(u8, sa, sb),
        .integer => |v| {
            var buf: [20]u8 = undefined;
            const sb = std.fmt.bufPrint(&buf, "{d}", .{v}) catch return .gt;
            return std.mem.order(u8, sa, sb);
        },
        .buffer => |bb| return std.mem.order(u8, sa, bb.data),
        else => return .gt,
    }
}

/// Buffer comparison: coerce second operand to buffer, then lexicographic.
/// Coercion rules (§19.3.5.7 Table 19.8):
///   Integer -> little-endian byte array, String -> raw bytes.
fn compare_as_buffer(ba: []const u8, b: Object) std.math.Order {
    switch (b) {
        .buffer => |bb| return std.mem.order(u8, ba, bb.data),
        .integer => |v| {
            const bytes = std.mem.asBytes(&v);
            // Trim trailing zero bytes for meaningful length
            var len: usize = @sizeOf(u64);
            while (len > 1 and bytes[len - 1] == 0) len -= 1;
            return std.mem.order(u8, ba, bytes[0..len]);
        },
        .string => |sb| return std.mem.order(u8, ba, sb),
        else => return .gt,
    }
}

// -- Public comparison opcodes -----------------------------------------------

/// DefLEqual := LequalOp Operand Operand (§20.2.5.4, LequalOp = 0x93).
pub fn eval_lequal(ectx: *EvalContext) Error!Object {
    const a = try eval_operand(ectx);
    const b = try eval_operand(ectx);
    return bool_obj(compare(a, b) == .eq);
}

/// DefLGreater := LgreaterOp Operand Operand (§20.2.5.4, LgreaterOp = 0x94).
pub fn eval_lgreater(ectx: *EvalContext) Error!Object {
    const a = try eval_operand(ectx);
    const b = try eval_operand(ectx);
    return bool_obj(compare(a, b) == .gt);
}

/// DefLLess := LlessOp Operand Operand (§20.2.5.4, LlessOp = 0x95).
pub fn eval_lless(ectx: *EvalContext) Error!Object {
    const a = try eval_operand(ectx);
    const b = try eval_operand(ectx);
    return bool_obj(compare(a, b) == .lt);
}

/// DefLAnd := LandOp Operand Operand (§20.2.5.4, LandOp = 0x90).
pub fn eval_land(ectx: *EvalContext) Error!Object {
    const a = to_int(try eval_operand(ectx));
    const b = to_int(try eval_operand(ectx));
    return bool_obj(a != 0 and b != 0);
}

/// DefLOr := LorOp Operand Operand (§20.2.5.4, LorOp = 0x91).
pub fn eval_lor(ectx: *EvalContext) Error!Object {
    const a = to_int(try eval_operand(ectx));
    const b = to_int(try eval_operand(ectx));
    return bool_obj(a != 0 or b != 0);
}

/// DefLNot := LnotOp Operand (§20.2.5.4, LnotOp = 0x92).
///
/// Also handles compound forms where LNot precedes another comparison:
///   LNotEqual     = LNot(LEqual(a,b))     -> 0x92 0x93
///   LLessEqual    = LNot(LGreater(a,b))   -> 0x92 0x94
///   LGreaterEqual = LNot(LLess(a,b))      -> 0x92 0x95
pub fn eval_lnot(ectx: *EvalContext) Error!Object {
    const next = ectx.stream.peek() orelse {
        return bool_obj(true);
    };

    // Check for compound forms (§20.2.5.4)
    switch (next) {
        0x93 => { // LNotEqual = LNot(LEqual)
            _ = ectx.stream.read_byte();
            const a = try eval_operand(ectx);
            const b = try eval_operand(ectx);
            return bool_obj(compare(a, b) != .eq);
        },
        0x94 => { // LLessEqual = LNot(LGreater)
            _ = ectx.stream.read_byte();
            const a = try eval_operand(ectx);
            const b = try eval_operand(ectx);
            return bool_obj(compare(a, b) != .gt);
        },
        0x95 => { // LGreaterEqual = LNot(LLess)
            _ = ectx.stream.read_byte();
            const a = try eval_operand(ectx);
            const b = try eval_operand(ectx);
            return bool_obj(compare(a, b) != .lt);
        },
        else => {
            // Plain LNot: invert the operand
            const a = to_int(try eval_operand(ectx));
            return bool_obj(a == 0);
        },
    }
}
