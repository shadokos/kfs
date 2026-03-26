/// ExternalOp handler (0x15, §19.6.45, §20.2.5.2).
///
/// ASL: External (ObjectName, ObjectType, ReturnType, ParameterTypes)
/// AML: DefExternal := ExternalOp NameString ObjectType ArgumentCount
///
/// Declares objects defined in other definition blocks (e.g., SSDTs
/// referencing DSDT objects). Informational only; skipped during namespace
/// loading. The AML compiler uses this to avoid undeclared-name errors.
const opcodes = @import("../opcodes.zig");
const skip = @import("../skip.zig");
const handlers = @import("../handlers.zig");

const Error = handlers.Error;
const HandleContext = handlers.HandleContext;

pub const opcode: u8 = opcodes.EXTERNAL_OP;

pub fn handle(ctx: HandleContext) Error!void {
    _ = ctx.stream.read_byte(); // ExternalOp
    skip.skip_name_path(ctx.stream);
    _ = ctx.stream.read_byte(); // ObjectType
    _ = ctx.stream.read_byte(); // ArgumentCount
}
