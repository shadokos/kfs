/// EXT_DEVICE_OP handler (0x5B 0x82, §19.6.31, §20.2.5.2).
///
/// ASL: Device (DeviceName) {TermList}
/// AML: DefDevice := DeviceOp PkgLength NameString TermList
///
/// Declares a hardware device package (processor, bus, or device); opens a name scope.
const parser = @import("../parser.zig");
const opcodes = @import("../opcodes.zig");
const handlers = @import("../handlers.zig");
const common = @import("common.zig");

const Stream = parser.Stream;
const Error = handlers.Error;
const HandleContext = handlers.HandleContext;

pub const ext_opcode: u8 = opcodes.EXT_DEVICE_OP;

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

    var target = ctx.scope;
    if (parsed.segments.len > 0) {
        const resolved = try common.resolve_parent(ctx.ns, ctx.scope, &parsed);

        if (resolved.parent.find_child(resolved.name)) |existing| {
            existing.node_type = .device;
            existing.object = .device;
            target = existing;
        } else {
            target = ctx.ns.alloc_node(
                resolved.name,
                .device,
            ) catch return Error.out_of_nodes;
            target.object = .device;
            resolved.parent.add_child(target);
        }
    }

    // Recurse into the device body
    if (end_pos > ctx.stream.pos) {
        var body = Stream{
            .data = ctx.stream.data[ctx.stream.pos..end_pos],
        };
        ctx.parse_term_list(ctx.ns, target, &body);
    }
    ctx.stream.pos = @min(end_pos, ctx.stream.data.len);
}
