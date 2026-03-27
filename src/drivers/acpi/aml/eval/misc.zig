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
