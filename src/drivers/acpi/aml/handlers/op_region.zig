/// EXT_OP_REGION_OP handler (0x5B 0x80, §20.2.5.2).
///
/// DefOpRegion := OpRegionOp NameString RegionSpace RegionOffset RegionLen
///
/// Note: OpRegion does NOT have a PkgLength (unlike most extended opcodes).
const opcodes = @import("../opcodes.zig");
const data = @import("../data.zig");
const handlers = @import("../handlers.zig");
const common = @import("common.zig");

const Error = handlers.Error;
const HandleContext = handlers.HandleContext;

pub const ext_opcode: u8 = opcodes.EXT_OP_REGION_OP;

pub fn handle(ctx: HandleContext) Error!void {
    const parsed = try common.parse_name_path(
        ctx.alloc,
        ctx.stream.data[ctx.stream.pos..],
    ) orelse return Error.parse_error;
    defer parsed.deinit(ctx.alloc);
    ctx.stream.pos += parsed.bytes_consumed;

    const space_byte = ctx.stream.read_byte() orelse
        return Error.parse_error;
    const offset = data.parse_integer_data(ctx.stream);
    const length = data.parse_integer_data(ctx.stream);

    if (parsed.segments.len > 0) {
        const resolved = try common.resolve_parent(ctx.ns, ctx.scope, &parsed);

        const node = ctx.ns.alloc_node(
            resolved.name,
            .op_region,
        ) catch return Error.out_of_nodes;
        node.object = .{
            .op_region = .{
                .space = @enumFromInt(space_byte),
                .offset = offset,
                .length = length,
            },
        };
        resolved.parent.add_child(node);
    }
}
