/// MethodOp handler (0x14, §20.2.5.2).
///
/// DefMethod := MethodOp PkgLength NameString MethodFlags TermList
///
/// Creates a method node in the namespace. The method body (TermList)
/// is NOT executed; only the bytecode slice is recorded for later
/// evaluation by the executor.
const parser = @import("../parser.zig");
const opcodes = @import("../opcodes.zig");
const handlers = @import("../handlers.zig");
const common = @import("common.zig");

const Error = handlers.Error;
const HandleContext = handlers.HandleContext;

/// MethodFlags byte layout (§20.2.5.2):
///   bits [2:0]  ArgCount (0-7)
///   bit  [3]    SerializeFlag (0=NotSerialized, 1=Serialized)
///   bits [7:4]  SyncLevel (0x0-0xF)
const MethodFlags = packed struct(u8) {
    arg_count: u3,
    serialized: bool,
    sync_level: u4,
};

pub const opcode: u8 = opcodes.METHOD_OP;

pub fn handle(ctx: HandleContext) Error!void {
    _ = ctx.stream.read_byte(); // MethodOp

    const pkg = parser.decode_pkg_length(ctx.stream) orelse
        return Error.parse_error;
    const end_pos = ctx.stream.pos + pkg.body_length;

    const parsed = try common.parse_name_path(
        ctx.alloc,
        ctx.stream.data[ctx.stream.pos..],
    ) orelse return Error.parse_error;
    defer parsed.deinit(ctx.alloc);
    ctx.stream.pos += parsed.bytes_consumed;

    const flags: MethodFlags = @bitCast(ctx.stream.read_byte() orelse
        return Error.parse_error);

    const code_len = end_pos -| ctx.stream.pos;
    const code = if (code_len > 0 and ctx.stream.pos + code_len <= ctx.stream.data.len)
        ctx.stream.data[ctx.stream.pos .. ctx.stream.pos + code_len]
    else
        &[_]u8{};

    if (parsed.segments.len > 0) {
        const resolved = try common.resolve_parent(ctx.ns, ctx.scope, &parsed);

        const node = ctx.ns.alloc_node(
            resolved.name,
            .method,
        ) catch return Error.out_of_nodes;
        node.object = .{
            .method = .{
                .arg_count = flags.arg_count,
                .serialized = flags.serialized,
                .sync_level = flags.sync_level,
                .code = code,
            },
        };
        resolved.parent.add_child(node);
    }

    ctx.stream.pos = @min(end_pos, ctx.stream.data.len);
}
