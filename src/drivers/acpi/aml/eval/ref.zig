/// Reference-type expression opcodes (ACPI 6.4 §20.2.5.4).
///
/// DefRefOf   := RefOfOp SuperName          (§20.2.5.4, RefOfOp = 0x71)
/// DefDerefOf := DerefOfOp ObjReference     (§20.2.5.4, DerefOfOp = 0x83)
/// DefIndex   := IndexOp BuffPkgStrObj IndexValue Target (§20.2.5.4, IndexOp = 0x88)
const objects = @import("../objects.zig");
const integer = @import("integer.zig");
const skip = @import("../skip.zig");
const store = @import("store.zig");
const opcodes = @import("../opcodes.zig");
const path_mod = @import("../../namespace/path.zig");

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

    const result: Object = switch (source) {
        .buffer => |b| if (index < b.data.len)
            .{ .integer = b.data[index] }
        else
            .{ .integer = 0 },
        .string => |s| if (index < s.len)
            .{ .integer = s[index] }
        else
            .{ .integer = 0 },
        .package => |p| if (index < p.elements.len)
            p.elements[index]
        else
            .{ .integer = 0 },
        else => .{ .integer = 0 },
    };

    try store.write_target(ectx, result);
    return result;
}

/// Evaluate DefRefOf. RefOfOp (0x71) must already be consumed.
/// SuperName := SimpleName | DebugObj | ReferenceTypeOpcode (§20.2.2)
/// SimpleName := NameString | ArgObj | LocalObj
/// Returns the object that the SuperName refers to.
pub fn eval_ref_of(ectx: *EvalContext) Error!Object {
    const b = ectx.stream.peek() orelse return .uninitialized;
    const frame = ectx.ctx.current() orelse return .uninitialized;

    // LocalObj (§20.2.6.2)
    if (b >= opcodes.LOCAL0 and b <= opcodes.LOCAL7) {
        _ = ectx.stream.read_byte();
        return frame.locals[b - opcodes.LOCAL0];
    }

    // ArgObj (§20.2.6.1)
    if (b >= opcodes.ARG0 and b <= opcodes.ARG6) {
        _ = ectx.stream.read_byte();
        return frame.args[b - opcodes.ARG0];
    }

    // DebugObj (§20.2.6.3)
    if (b == opcodes.EXT_PREFIX) {
        if (ectx.stream.pos + 1 < ectx.stream.data.len and
            ectx.stream.data[ectx.stream.pos + 1] == opcodes.EXT_DEBUG_OP)
        {
            _ = ectx.stream.read_byte();
            _ = ectx.stream.read_byte();
            return .debug_object;
        }
    }

    // NameString: resolve in namespace and return the object
    if (path_mod.is_name_start(b)) {
        const parsed = path_mod.parse(
            ectx.alloc,
            ectx.stream.data[ectx.stream.pos..],
        ) catch return .uninitialized;
        if (parsed) |p| {
            defer p.deinit(ectx.alloc);
            ectx.stream.pos += p.bytes_consumed;
            if (ectx.ns.resolve(frame.scope, &p)) |node| {
                return node.object;
            }
        }
        return .uninitialized;
    }

    // Fallback: skip and return uninitialized
    skip.skip_super_name(ectx.stream);
    return .uninitialized;
}
