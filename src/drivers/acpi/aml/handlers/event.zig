/// EXT_EVENT_OP handler (0x5B 0x02, §19.6.41, §20.2.5.2).
///
/// ASL: Event (EventName)
/// AML: DefEvent := EventOp NameString
///
/// Declares an event synchronization object.
const parser = @import("../parser.zig");
const opcodes = @import("../opcodes.zig");
const handlers = @import("../handlers.zig");
const common = @import("common.zig");

const Stream = parser.Stream;
const Error = handlers.Error;
const HandleContext = handlers.HandleContext;

pub const ext_opcode: u8 = opcodes.EXT_EVENT_OP;

pub fn handle(ctx: HandleContext) Error!void {
    const parsed = try common.parse_name_path(
        ctx.alloc,
        ctx.stream.data[ctx.stream.pos..],
    ) orelse return Error.parse_error;
    defer parsed.deinit(ctx.alloc);
    ctx.stream.pos += parsed.bytes_consumed;

    if (parsed.segments.len > 0) {
        const resolved = try common.resolve_parent(ctx.ns, ctx.scope, &parsed);

        if (resolved.parent.find_child(resolved.name)) |existing| {
            existing.node_type = .event;
            existing.object = .event;
        } else {
            const new_node = ctx.ns.alloc_node(
                resolved.name,
                .event,
            ) catch return Error.out_of_nodes;
            new_node.object = .event;
            resolved.parent.add_child(new_node);
        }
    }
}
