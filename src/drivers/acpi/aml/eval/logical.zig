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
/// All return Ones (integer 0xFFFFFFFF for rev 1) for true, Zero for false.
/// We follow the POC convention of returning 1/0 for clarity (both are
/// nonzero, so they work the same in boolean contexts).
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

/// DefLEqual := LequalOp Operand Operand (§20.2.5.4, LequalOp = 0x93).
pub fn eval_lequal(ectx: *EvalContext) Error!Object {
    const a = to_int(try eval_operand(ectx));
    const b = to_int(try eval_operand(ectx));
    return bool_obj(a == b);
}

/// DefLGreater := LgreaterOp Operand Operand (§20.2.5.4, LgreaterOp = 0x94).
pub fn eval_lgreater(ectx: *EvalContext) Error!Object {
    const a = to_int(try eval_operand(ectx));
    const b = to_int(try eval_operand(ectx));
    return bool_obj(a > b);
}

/// DefLLess := LlessOp Operand Operand (§20.2.5.4, LlessOp = 0x95).
pub fn eval_lless(ectx: *EvalContext) Error!Object {
    const a = to_int(try eval_operand(ectx));
    const b = to_int(try eval_operand(ectx));
    return bool_obj(a < b);
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
            const a = to_int(try eval_operand(ectx));
            const b = to_int(try eval_operand(ectx));
            return bool_obj(a != b);
        },
        0x94 => { // LLessEqual = LNot(LGreater)
            _ = ectx.stream.read_byte();
            const a = to_int(try eval_operand(ectx));
            const b = to_int(try eval_operand(ectx));
            return bool_obj(a <= b);
        },
        0x95 => { // LGreaterEqual = LNot(LLess)
            _ = ectx.stream.read_byte();
            const a = to_int(try eval_operand(ectx));
            const b = to_int(try eval_operand(ectx));
            return bool_obj(a >= b);
        },
        else => {
            // Plain LNot: invert the operand
            const a = to_int(try eval_operand(ectx));
            return bool_obj(a == 0);
        },
    }
}
