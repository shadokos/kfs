/// ScopeOp handler (0x10, §19.6.120, §20.2.5.1).
///
/// ASL: Scope (Location) {ObjectList}
/// AML: DefScope := ScopeOp PkgLength NameString TermList
///
/// Opens or creates a namespace scope (§19.6.120). If the target node already
/// exists (e.g., predefined scopes like \_SB), it is opened without changing
/// its node_type (§5.3).
const parser = @import("../parser.zig");
const opcodes = @import("../opcodes.zig");
const handlers = @import("../handlers.zig");
const common = @import("common.zig");

const Stream = parser.Stream;
const Error = handlers.Error;
const HandleContext = handlers.HandleContext;

pub const opcode: u8 = opcodes.SCOPE_OP;

pub fn handle(ctx: HandleContext) Error!void {
    _ = ctx.stream.read_byte(); // ScopeOp

    const pkg = parser.decode_pkg_length(ctx.stream) orelse
        return Error.parse_error;
    const end_pos = ctx.stream.pos + pkg.body_length;

    const parsed = try common.parse_name_path(
        ctx.alloc,
        ctx.stream.data[ctx.stream.pos..],
    ) orelse return Error.parse_error;
    defer parsed.deinit(ctx.alloc);
    ctx.stream.pos += parsed.bytes_consumed;

    const already_exists = ctx.ns.resolve(ctx.scope, &parsed) != null;

    const target = ctx.ns.resolve_or_create(
        ctx.scope,
        &parsed,
    ) catch return Error.out_of_nodes;

    // Only set node_type to .scope if this is a newly created node.
    // Scope() on existing nodes (root, device, etc.) just opens them
    // for adding children without changing their type.
    if (!already_exists) {
        target.node_type = .scope;
    }

    // Recurse into the scope body
    if (end_pos > ctx.stream.pos) {
        var body = Stream{
            .data = ctx.stream.data[ctx.stream.pos..end_pos],
        };
        ctx.parse_term_list(ctx.ns, target, &body);
    }
    ctx.stream.pos = @min(end_pos, ctx.stream.data.len);
}
