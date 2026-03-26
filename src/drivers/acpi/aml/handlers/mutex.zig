/// EXT_MUTEX_OP handler (0x5B 0x01, §19.6.88, §20.2.5.2).
///
/// ASL: Mutex (MutexName, SyncLevel)
/// AML: DefMutex := MutexOp NameString SyncFlags
///
/// SyncFlags byte layout (§20.2.5.2):
///   bits [3:0]  SyncLevel (0x0-0xF)
///   bits [7:4]  reserved (must be 0)
const opcodes = @import("../opcodes.zig");
const handlers = @import("../handlers.zig");
const common = @import("common.zig");

const Error = handlers.Error;
const HandleContext = handlers.HandleContext;

const MutexFlags = packed struct(u8) {
    sync_level: u4,
    _reserved: u4 = 0,
};

pub const ext_opcode: u8 = opcodes.EXT_MUTEX_OP;

pub fn handle(ctx: HandleContext) Error!void {
    const parsed = try common.parse_name_path(
        ctx.alloc,
        ctx.stream.data[ctx.stream.pos..],
    ) orelse return Error.parse_error;
    defer parsed.deinit(ctx.alloc);
    ctx.stream.pos += parsed.bytes_consumed;

    const flags: MutexFlags = @bitCast(ctx.stream.read_byte() orelse
        return Error.parse_error);

    if (parsed.segments.len > 0) {
        const resolved = try common.resolve_parent(ctx.ns, ctx.scope, &parsed);

        const node = ctx.ns.alloc_node(
            resolved.name,
            .mutex,
        ) catch return Error.out_of_nodes;
        node.object = .{
            .mutex = .{ .sync_level = flags.sync_level },
        };
        resolved.parent.add_child(node);
    }
}
