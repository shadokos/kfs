/// DefBuffer evaluation (ACPI 6.4 §20.2.5.4).
///
/// DefBuffer := BufferOp PkgLength BufferSize ByteList (§20.2.5.4)
/// BufferOp  := 0x11
/// BufferSize := TermArg => Integer
///
/// "Buffer declares a Buffer object. BufferSize specifies the size
/// (in bytes) of the buffer. It is evaluated as an integer." (§19.6.10)
const parser = @import("../parser.zig");
const objects = @import("../objects.zig");

const Object = objects.Object;
const Error = @import("executor.zig").Error;
const EvalContext = @import("executor.zig").EvalContext;

/// Evaluate DefBuffer. BufferOp (0x11) must already be consumed.
pub fn eval_buffer(ectx: *EvalContext) Error!Object {
    const operand = @import("operand.zig");
    const pkg = parser.decode_pkg_length(ectx.stream) orelse
        return Error.parse_error;
    const end = ectx.stream.pos + pkg.body_length;

    // BufferSize (TermArg => Integer)
    _ = try operand.eval_operand(ectx);

    // ByteList: raw initializer data (slice into the DSDT/SSDT bytecode)
    const data = if (end > ectx.stream.pos)
        ectx.stream.data[ectx.stream.pos..end]
    else
        &[_]u8{};

    ectx.stream.pos = @min(end, ectx.stream.data.len);
    return .{ .buffer = .{ .data = @constCast(data) } };
}
