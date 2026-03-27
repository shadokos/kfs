/// AML arithmetic expression opcodes (ACPI 6.4 §20.2.5.4).
///
/// All binary arithmetic ops share the grammar:
///   Def<Op> := <OpByte> Operand Operand Target
///   Operand := TermArg => Integer
///   Target  := SuperName | NullName
///
/// Exceptions:
///   DefNot       := NotOp Operand Target           (unary, §20.2.5.4)
///   DefDivide    := DivideOp Dividend Divisor Remainder Quotient (two targets, §20.2.5.4)
///   DefIncrement := IncrementOp SuperName           (§20.2.5.4)
///   DefDecrement := DecrementOp SuperName           (§20.2.5.4)
///   DefFindSetLeftBit  := FindSetLeftBitOp Operand Target  (§20.2.5.4)
///   DefFindSetRightBit := FindSetRightBitOp Operand Target (§20.2.5.4)
///
/// Results are masked to 32 bits for \_REV = 1 (§5.7.4).
const objects = @import("../objects.zig");
const integer = @import("integer.zig");
const store = @import("store.zig");

const Object = objects.Object;
const Error = @import("executor.zig").Error;
const EvalContext = @import("executor.zig").EvalContext;

const to_int = integer.to_int;
const mask32 = integer.mask32;

fn eval_operand(ectx: *EvalContext) Error!Object {
    return @import("operand.zig").eval_operand(ectx);
}

// -- Binary: Operand Operand Target ----------------------------------------

/// DefAdd := AddOp Operand Operand Target (§20.2.5.4, AddOp = 0x72).
pub fn eval_add(ectx: *EvalContext) Error!Object {
    const a = to_int(try eval_operand(ectx));
    const b = to_int(try eval_operand(ectx));
    const result: Object = .{ .integer = mask32(a +% b) };
    try store.write_target(ectx, result);
    return result;
}

/// DefSubtract := SubtractOp Operand Operand Target (§20.2.5.4, SubtractOp = 0x74).
pub fn eval_subtract(ectx: *EvalContext) Error!Object {
    const a = to_int(try eval_operand(ectx));
    const b = to_int(try eval_operand(ectx));
    const result: Object = .{ .integer = mask32(a -% b) };
    try store.write_target(ectx, result);
    return result;
}

/// DefMultiply := MultiplyOp Operand Operand Target (§20.2.5.4, MultiplyOp = 0x77).
pub fn eval_multiply(ectx: *EvalContext) Error!Object {
    const a = to_int(try eval_operand(ectx));
    const b = to_int(try eval_operand(ectx));
    const result: Object = .{ .integer = mask32(a *% b) };
    try store.write_target(ectx, result);
    return result;
}

/// DefAnd := AndOp Operand Operand Target (§20.2.5.4, AndOp = 0x7B).
pub fn eval_and(ectx: *EvalContext) Error!Object {
    const a = to_int(try eval_operand(ectx));
    const b = to_int(try eval_operand(ectx));
    const result: Object = .{ .integer = a & b };
    try store.write_target(ectx, result);
    return result;
}

/// DefNAnd := NandOp Operand Operand Target (§20.2.5.4, NandOp = 0x7C).
pub fn eval_nand(ectx: *EvalContext) Error!Object {
    const a = to_int(try eval_operand(ectx));
    const b = to_int(try eval_operand(ectx));
    const result: Object = .{ .integer = mask32(~(a & b)) };
    try store.write_target(ectx, result);
    return result;
}

/// DefOr := OrOp Operand Operand Target (§20.2.5.4, OrOp = 0x7D).
pub fn eval_or(ectx: *EvalContext) Error!Object {
    const a = to_int(try eval_operand(ectx));
    const b = to_int(try eval_operand(ectx));
    const result: Object = .{ .integer = a | b };
    try store.write_target(ectx, result);
    return result;
}

/// DefNOr := NorOp Operand Operand Target (§20.2.5.4, NorOp = 0x7E).
pub fn eval_nor(ectx: *EvalContext) Error!Object {
    const a = to_int(try eval_operand(ectx));
    const b = to_int(try eval_operand(ectx));
    const result: Object = .{ .integer = mask32(~(a | b)) };
    try store.write_target(ectx, result);
    return result;
}

/// DefXOr := XorOp Operand Operand Target (§20.2.5.4, XorOp = 0x7F).
pub fn eval_xor(ectx: *EvalContext) Error!Object {
    const a = to_int(try eval_operand(ectx));
    const b = to_int(try eval_operand(ectx));
    const result: Object = .{ .integer = a ^ b };
    try store.write_target(ectx, result);
    return result;
}

/// DefShiftLeft := ShiftLeftOp Operand ShiftCount Target (§20.2.5.4, ShiftLeftOp = 0x79).
pub fn eval_shift_left(ectx: *EvalContext) Error!Object {
    const a = to_int(try eval_operand(ectx));
    const b = to_int(try eval_operand(ectx));
    const shift: u6 = @truncate(b);
    const result: Object = .{ .integer = mask32(a << shift) };
    try store.write_target(ectx, result);
    return result;
}

/// DefShiftRight := ShiftRightOp Operand ShiftCount Target (§20.2.5.4, ShiftRightOp = 0x7A).
pub fn eval_shift_right(ectx: *EvalContext) Error!Object {
    const a = to_int(try eval_operand(ectx));
    const b = to_int(try eval_operand(ectx));
    const shift: u6 = @truncate(b);
    const result: Object = .{ .integer = mask32(a >> shift) };
    try store.write_target(ectx, result);
    return result;
}

/// DefMod := ModOp Dividend Divisor Target (§20.2.5.4, ModOp = 0x85).
pub fn eval_mod(ectx: *EvalContext) Error!Object {
    const dividend = to_int(try eval_operand(ectx));
    const divisor = to_int(try eval_operand(ectx));
    if (divisor == 0) return Error.division_by_zero;
    const result: Object = .{ .integer = dividend % divisor };
    try store.write_target(ectx, result);
    return result;
}

// -- Unary with target -----------------------------------------------------

/// DefNot := NotOp Operand Target (§20.2.5.4, NotOp = 0x80).
pub fn eval_not(ectx: *EvalContext) Error!Object {
    const a = to_int(try eval_operand(ectx));
    const result: Object = .{ .integer = mask32(~a) };
    try store.write_target(ectx, result);
    return result;
}

// -- Divide (two targets) --------------------------------------------------

/// DefDivide := DivideOp Dividend Divisor Remainder Quotient (§20.2.5.4, DivideOp = 0x78).
/// Note: the two Target operands are Remainder first, then Quotient.
pub fn eval_divide(ectx: *EvalContext) Error!Object {
    const dividend = to_int(try eval_operand(ectx));
    const divisor = to_int(try eval_operand(ectx));
    if (divisor == 0) return Error.division_by_zero;
    const remainder: Object = .{ .integer = dividend % divisor };
    const quotient: Object = .{ .integer = dividend / divisor };
    try store.write_target(ectx, remainder);
    try store.write_target(ectx, quotient);
    return quotient;
}

// -- Increment / Decrement -------------------------------------------------

/// DefIncrement := IncrementOp SuperName (§20.2.5.4, IncrementOp = 0x75).
/// Reads the current value from the SuperName, increments, writes back.
pub fn eval_increment(ectx: *EvalContext) Error!Object {
    const saved_pos = ectx.stream.pos;
    const current_val = to_int(try eval_operand(ectx));
    const result: Object = .{ .integer = mask32(current_val +% 1) };
    // Rewind to write back to the same SuperName
    ectx.stream.pos = saved_pos;
    try store.write_super_name_pub(ectx, result);
    return result;
}

/// DefDecrement := DecrementOp SuperName (§20.2.5.4, DecrementOp = 0x76).
pub fn eval_decrement(ectx: *EvalContext) Error!Object {
    const saved_pos = ectx.stream.pos;
    const current_val = to_int(try eval_operand(ectx));
    const result: Object = .{ .integer = mask32(current_val -% 1) };
    ectx.stream.pos = saved_pos;
    try store.write_super_name_pub(ectx, result);
    return result;
}

// -- FindSetLeftBit / FindSetRightBit --------------------------------------

/// DefFindSetLeftBit := FindSetLeftBitOp Operand Target (§20.2.5.4, 0x81).
/// Returns the 1-based bit position of the most significant set bit, or 0 if none.
pub fn eval_find_set_left_bit(ectx: *EvalContext) Error!Object {
    const val = to_int(try eval_operand(ectx));
    const result: Object = .{
        .integer = if (val == 0) 0 else 32 - @as(u64, @clz(@as(u32, @truncate(val)))),
    };
    try store.write_target(ectx, result);
    return result;
}

/// DefFindSetRightBit := FindSetRightBitOp Operand Target (§20.2.5.4, 0x82).
/// Returns the 1-based bit position of the least significant set bit, or 0 if none.
pub fn eval_find_set_right_bit(ectx: *EvalContext) Error!Object {
    const val = to_int(try eval_operand(ectx));
    const result: Object = .{
        .integer = if (val == 0) 0 else @as(u64, @ctz(@as(u32, @truncate(val)))) + 1,
    };
    try store.write_target(ectx, result);
    return result;
}
