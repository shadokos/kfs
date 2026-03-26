/// NameOp handler (0x08, §19.6.89, §20.2.5.1).
///
/// ASL: Name (ObjectName, Object)
/// AML: DefName := NameOp NameString DataRefObject
///
/// Creates a named constant object in the namespace at the current scope.
const opcodes = @import("../opcodes.zig");
const data = @import("../data.zig");
const handlers = @import("../handlers.zig");
const common = @import("common.zig");

const Error = handlers.Error;
const HandleContext = handlers.HandleContext;

pub const opcode: u8 = opcodes.NAME_OP;

pub fn handle(ctx: HandleContext) Error!void {
    _ = ctx.stream.read_byte(); // NameOp

    const parsed = try common.parse_name_path(
        ctx.alloc,
        ctx.stream.data[ctx.stream.pos..],
    ) orelse return Error.parse_error;
    defer parsed.deinit(ctx.alloc);
    ctx.stream.pos += parsed.bytes_consumed;

    // Parse the data object value
    const obj = data.parse_data_object(ctx.stream);

    if (parsed.segments.len == 0) return;

    // Navigate to parent scope and create the leaf
    const name = parsed.segments[parsed.segments.len - 1];

    const parent = if (parsed.segments.len > 1) blk: {
        var parent_parsed = parsed;
        parent_parsed.segments = parsed.segments[0 .. parsed.segments.len - 1];
        break :blk ctx.ns.resolve_or_create(
            ctx.scope,
            &parent_parsed,
        ) catch return Error.out_of_nodes;
    } else blk: {
        break :blk if (parsed.is_absolute) ctx.ns.root else ctx.scope;
    };

    // Check if node already exists (e.g., predefined object)
    if (parent.find_child(name)) |existing| {
        existing.object = obj;
        existing.node_type = .name;
    } else {
        const node = ctx.ns.alloc_node(
            name,
            .name,
        ) catch return Error.out_of_nodes;
        node.object = obj;
        parent.add_child(node);
    }
}
