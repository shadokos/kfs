/// Miscellaneous expression opcodes (ACPI 6.4 §20.2.5.4).
///
/// DefSizeOf    := SizeOfOp SuperName             (§20.2.5.4, SizeOfOp = 0x87)
/// DefObjectType := ObjectTypeOp <SimpleName | DebugObj | RefOf | DerefOf | Index>
///                                                (§20.2.5.4, ObjectTypeOp = 0x8E)
/// DefCopyObject := CopyObjectOp TermArg SimpleName (§20.2.5.4, CopyObjectOp = 0x9D)
const objects = @import("../objects.zig");
const integer = @import("integer.zig");
const skip = @import("../skip.zig");

const Object = objects.Object;
const Error = @import("executor.zig").Error;
const EvalContext = @import("executor.zig").EvalContext;

/// Evaluate DefSizeOf. SizeOfOp (0x87) must already be consumed.
/// Returns the size of a Buffer, String, or Package (§19.6.124).
pub fn eval_size_of(ectx: *EvalContext) Error!Object {
    const operand = @import("operand.zig");
    const obj = try operand.eval_operand(ectx);
    const size: u64 = switch (obj) {
        .string => |s| s.len,
        .buffer => |b| b.data.len,
        .package => |p| p.elements.len,
        else => 0,
    };
    return .{ .integer = size };
}

/// Evaluate DefObjectType. ObjectTypeOp (0x8E) must already be consumed.
/// Returns the type of the object per §19.6.96, Table 19.36.
pub fn eval_object_type(ectx: *EvalContext) Error!Object {
    const operand = @import("operand.zig");
    const obj = try operand.eval_operand(ectx);
    return .{ .integer = obj.spec_type() };
}

/// Evaluate DefCopyObject. CopyObjectOp (0x9D) must already be consumed.
/// DefCopyObject := CopyObjectOp TermArg SimpleName (§20.2.5.4)
pub fn eval_copy_object(ectx: *EvalContext) Error!Object {
    const operand = @import("operand.zig");
    const store_mod = @import("store.zig");
    const val = try operand.eval_operand(ectx);
    try store_mod.write_super_name_pub(ectx, val);
    return val;
}

/// Evaluate DefMatch. MatchOp (0x89) must already be consumed.
/// DefMatch := MatchOp SearchPkg MatchOpcode Operand MatchOpcode Operand StartIndex
/// Returns the index of the first package element that satisfies both match
/// conditions, or ONES (0xFFFFFFFF) if no match is found.
/// MatchOpcode: MTR=0, MEQ=1, MLE=2, MLT=3, MGE=4, MGT=5
pub fn eval_match(ectx: *EvalContext) Error!Object {
    const operand = @import("operand.zig");
    const pkg = try operand.eval_operand(ectx);
    const op1_byte = ectx.stream.read_byte() orelse return Error.parse_error;
    const val1 = integer.to_int(try operand.eval_operand(ectx));
    const op2_byte = ectx.stream.read_byte() orelse return Error.parse_error;
    const val2 = integer.to_int(try operand.eval_operand(ectx));
    const start_index = @as(usize, @intCast(integer.to_int(try operand.eval_operand(ectx))));

    const elements = switch (pkg) {
        .package => |p| p.elements,
        else => return .{ .integer = 0xFFFFFFFF },
    };

    var i: usize = start_index;
    while (i < elements.len) : (i += 1) {
        const elem_val = integer.to_int(elements[i]);
        if (match_compare(op1_byte, elem_val, val1) and
            match_compare(op2_byte, elem_val, val2))
        {
            return .{ .integer = @as(u64, i) };
        }
    }
    return .{ .integer = 0xFFFFFFFF }; // ONES = not found
}

/// Evaluate a single match predicate (§19.6.80 Table 19.30).
fn match_compare(op: u8, pkg_elem: u64, operand_val: u64) bool {
    return switch (op) {
        0 => true, // MTR - always true
        1 => pkg_elem == operand_val, // MEQ
        2 => pkg_elem <= operand_val, // MLE
        3 => pkg_elem < operand_val, // MLT
        4 => pkg_elem >= operand_val, // MGE
        5 => pkg_elem > operand_val, // MGT
        else => true,
    };
}
