/// ALIAS_OP handler (0x06, §20.2.5.1).
///
/// DefAlias := AliasOp NameString NameString (§20.2.5.1)
///
/// Creates an alias: the second NameString becomes an alternate name
/// for the object referred to by the first NameString (§19.6.4).
const opcodes = @import("../opcodes.zig");
const handlers = @import("../handlers.zig");
const common = @import("common.zig");

const Error = handlers.Error;
const HandleContext = handlers.HandleContext;

pub const opcode: u8 = opcodes.ALIAS_OP;

pub fn handle(ctx: HandleContext) Error!void {
    _ = ctx.stream.read_byte(); // ALIAS_OP

    // Source name (existing object)
    const source_parsed = try common.parse_name_path(
        ctx.alloc,
        ctx.stream.data[ctx.stream.pos..],
    ) orelse return;
    defer source_parsed.deinit(ctx.alloc);
    ctx.stream.pos += source_parsed.bytes_consumed;

    // Alias name (new name)
    const alias_parsed = try common.parse_name_path(
        ctx.alloc,
        ctx.stream.data[ctx.stream.pos..],
    ) orelse return;
    defer alias_parsed.deinit(ctx.alloc);
    ctx.stream.pos += alias_parsed.bytes_consumed;

    // Resolve source object
    const source_node = ctx.ns.resolve(ctx.scope, &source_parsed) orelse return;

    // Create alias node with same object
    const resolved = try common.resolve_parent(ctx.ns, ctx.scope, &alias_parsed);
    if (resolved.parent.find_child(resolved.name)) |existing| {
        existing.object = source_node.object;
        existing.node_type = source_node.node_type;
    } else {
        const node = ctx.ns.alloc_node(resolved.name, source_node.node_type) catch return;
        node.object = source_node.object;
        resolved.parent.add_child(node);
    }
}
