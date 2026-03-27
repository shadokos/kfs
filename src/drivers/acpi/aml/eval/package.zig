/// DefPackage and DefVarPackage evaluation (ACPI 6.4 §20.2.5.4).
///
/// DefPackage    := PackageOp PkgLength NumElements PackageElementList (§20.2.5.4)
/// PackageOp     := 0x12
/// NumElements   := ByteData
///
/// DefVarPackage := VarPackageOp PkgLength VarNumElements PackageElementList (§20.2.5.4)
/// VarPackageOp  := 0x13
/// VarNumElements := TermArg => Integer
///
/// PackageElement := DataRefObject | NameString (§20.2.5.4)
const parser = @import("../parser.zig");
const objects = @import("../objects.zig");
const integer = @import("integer.zig");
const osl = @import("../../os_layer.zig");

const Object = objects.Object;
const Error = @import("executor.zig").Error;
const EvalContext = @import("executor.zig").EvalContext;

/// Evaluate DefPackage. PackageOp (0x12) must already be consumed.
pub fn eval_package(ectx: *EvalContext) Error!Object {
    const operand = @import("operand.zig");
    const pkg = parser.decode_pkg_length(ectx.stream) orelse
        return Error.parse_error;
    const end = ectx.stream.pos + pkg.body_length;

    const num_elements: usize = ectx.stream.read_byte() orelse
        return Error.parse_error;

    const elements = osl.kmalloc(Object, num_elements) orelse
        return Error.out_of_nodes;

    var i: usize = 0;
    while (ectx.stream.pos < end and i < num_elements) : (i += 1) {
        elements[i] = operand.eval_operand(ectx) catch .uninitialized;
    }
    while (i < num_elements) : (i += 1) {
        elements[i] = .uninitialized;
    }

    ectx.stream.pos = @min(end, ectx.stream.data.len);
    return .{ .package = .{ .elements = elements } };
}

/// Evaluate DefVarPackage. VarPackageOp (0x13) must already be consumed.
pub fn eval_var_package(ectx: *EvalContext) Error!Object {
    const operand = @import("operand.zig");
    const pkg = parser.decode_pkg_length(ectx.stream) orelse
        return Error.parse_error;
    const end = ectx.stream.pos + pkg.body_length;

    const num_elements_obj = try operand.eval_operand(ectx);
    const num_elements = @as(usize, @intCast(integer.to_int(num_elements_obj)));

    const elements = osl.kmalloc(Object, num_elements) orelse
        return Error.out_of_nodes;

    var i: usize = 0;
    while (ectx.stream.pos < end and i < num_elements) : (i += 1) {
        elements[i] = operand.eval_operand(ectx) catch .uninitialized;
    }
    while (i < num_elements) : (i += 1) {
        elements[i] = .uninitialized;
    }

    ectx.stream.pos = @min(end, ectx.stream.data.len);
    return .{ .package = .{ .elements = elements } };
}
