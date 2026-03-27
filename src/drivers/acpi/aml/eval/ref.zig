/// Reference-type expression opcodes (ACPI 6.4 §20.2.5.4).
///
/// DefRefOf   := RefOfOp SuperName          (§20.2.5.4, RefOfOp = 0x71)
/// DefDerefOf := DerefOfOp ObjReference     (§20.2.5.4, DerefOfOp = 0x83)
/// DefIndex   := IndexOp BuffPkgStrObj IndexValue Target (§20.2.5.4, IndexOp = 0x88)
const objects = @import("../objects.zig");
const integer = @import("integer.zig");
const skip = @import("../skip.zig");
const store = @import("store.zig");

const Object = objects.Object;
const Error = @import("executor.zig").Error;
const EvalContext = @import("executor.zig").EvalContext;

/// Evaluate DefDerefOf. DerefOfOp (0x83) must already be consumed.
/// In our simplified model, just evaluate the inner expression.
pub fn eval_deref_of(ectx: *EvalContext) Error!Object {
    return @import("operand.zig").eval_operand(ectx);
}

/// Evaluate DefIndex. IndexOp (0x88) must already be consumed.
/// DefIndex := IndexOp BuffPkgStrObj IndexValue Target (§20.2.5.4)
pub fn eval_index(ectx: *EvalContext) Error!Object {
    const operand = @import("operand.zig");
    const source = try operand.eval_operand(ectx);
    const index = @as(usize, @intCast(integer.to_int(try operand.eval_operand(ectx))));
    // Skip the Target (result is returned directly)
    skip.skip_target(ectx.stream);

    switch (source) {
        .buffer => |b| {
            if (index < b.data.len) {
                return .{ .integer = b.data[index] };
            }
        },
        .string => |s| {
            if (index < s.len) {
                return .{ .integer = s[index] };
            }
        },
        .package => |p| {
            if (index < p.elements.len) {
                return p.elements[index];
            }
        },
        else => {},
    }
    return .{ .integer = 0 };
}

/// Evaluate DefRefOf. RefOfOp (0x71) must already be consumed.
/// Simplified: just skip the SuperName and return uninitialized.
pub fn eval_ref_of(ectx: *EvalContext) Error!Object {
    skip.skip_super_name(ectx.stream);
    return .uninitialized;
}
