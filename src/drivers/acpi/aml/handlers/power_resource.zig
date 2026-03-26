/// EXT_POWER_RES_OP handler (0x5B 0x84, §19.6.107, §20.2.5.2).
///
/// DefPowerRes := PowerResOp PkgLength NameString SystemLevel ResourceOrder TermList (§20.2.5.2)
///        SystemLevel := ByteData, ResourceOrder := WordData
const parser = @import("../parser.zig");
const opcodes = @import("../opcodes.zig");
const handlers = @import("../handlers.zig");
const common = @import("common.zig");

const Stream = parser.Stream;
const Error = handlers.Error;
const HandleContext = handlers.HandleContext;

pub const ext_opcode: u8 = opcodes.EXT_POWER_RES_OP;

pub fn handle(ctx: HandleContext) Error!void {
    const pkg = parser.decode_pkg_length(ctx.stream) orelse
        return Error.parse_error;
    const end_pos = ctx.stream.pos + pkg.body_length;

    const parsed = try common.parse_name_path(
        ctx.alloc,
        ctx.stream.data[ctx.stream.pos..],
    ) orelse return Error.parse_error;
    defer parsed.deinit(ctx.alloc);
    ctx.stream.pos += parsed.bytes_consumed;

    const system_level = ctx.stream.read_byte() orelse
        return Error.parse_error;
    const resource_order = ctx.stream.read_word() orelse
        return Error.parse_error;

    if (parsed.segments.len > 0) {
        const resolved = try common.resolve_parent(ctx.ns, ctx.scope, &parsed);

        const target = ctx.ns.alloc_node(
            resolved.name,
            .power_resource,
        ) catch return Error.out_of_nodes;
        target.object = .{
            .power_resource = .{
                .system_level = system_level,
                .resource_order = resource_order,
            },
        };
        resolved.parent.add_child(target);

        if (end_pos > ctx.stream.pos) {
            var body = Stream{
                .data = ctx.stream.data[ctx.stream.pos..end_pos],
            };
            ctx.parse_term_list(ctx.ns, target, &body);
        }
    }
    ctx.stream.pos = @min(end_pos, ctx.stream.data.len);
}
