/// EXT_INDEX_FIELD_OP handler (0x5B 0x86, §20.2.5.2).
///
/// DefIndexField := IndexFieldOp PkgLength NameString NameString FieldFlags FieldList
///
/// Creates index field unit nodes connecting named bit ranges to
/// index/data register pairs.
const parser = @import("../parser.zig");
const opcodes = @import("../opcodes.zig");
const path_mod = @import("../../namespace/path.zig");
const skip = @import("../skip.zig");
const handlers = @import("../handlers.zig");
const common = @import("common.zig");
const objects = @import("../objects.zig");

const Node = @import("../../namespace/node.zig").Node;
const Error = handlers.Error;
const HandleContext = handlers.HandleContext;

/// FieldFlags byte layout (§20.2.5.2):
///   bits [3:0]  AccessType
///   bit  [4]    LockRule (0=NoLock, 1=Lock)
///   bits [6:5]  UpdateRule
///   bit  [7]    reserved
const FieldFlags = packed struct(u8) {
    access_type: objects.AccessType,
    lock_rule: bool,
    update_rule: objects.UpdateRule,
    _reserved: u1 = 0,
};

pub const ext_opcode: u8 = opcodes.EXT_INDEX_FIELD_OP;

pub fn handle(ctx: HandleContext) Error!void {
    const pkg = parser.decode_pkg_length(ctx.stream) orelse
        return Error.parse_error;
    const end_pos = ctx.stream.pos + pkg.body_length;

    // Index register name
    const index_parsed = try common.parse_name_path(
        ctx.alloc,
        ctx.stream.data[ctx.stream.pos..],
    ) orelse {
        ctx.stream.pos = @min(end_pos, ctx.stream.data.len);
        return;
    };
    defer index_parsed.deinit(ctx.alloc);
    ctx.stream.pos += index_parsed.bytes_consumed;

    var index_name: [4]u8 = "____".*;
    if (index_parsed.segments.len > 0) {
        index_name = index_parsed.segments[index_parsed.segments.len - 1];
    }

    // Data register name
    const data_parsed = try common.parse_name_path(
        ctx.alloc,
        ctx.stream.data[ctx.stream.pos..],
    ) orelse {
        ctx.stream.pos = @min(end_pos, ctx.stream.data.len);
        return;
    };
    defer data_parsed.deinit(ctx.alloc);
    ctx.stream.pos += data_parsed.bytes_consumed;

    var data_name: [4]u8 = "____".*;
    if (data_parsed.segments.len > 0) {
        data_name = data_parsed.segments[data_parsed.segments.len - 1];
    }

    // Resolve index and data field nodes
    const index_node: ?*Node = ctx.ns.resolve(ctx.scope, &index_parsed);
    const data_node: ?*Node = ctx.ns.resolve(ctx.scope, &data_parsed);

    // Field flags
    const flags: FieldFlags = @bitCast(ctx.stream.read_byte() orelse {
        ctx.stream.pos = @min(end_pos, ctx.stream.data.len);
        return;
    });

    // Parse FieldList (same encoding as DefField FieldList, §20.2.5.2)
    var bit_offset: u32 = 0;
    while (ctx.stream.pos < end_pos) {
        const b = ctx.stream.peek() orelse break;

        if (b == 0x00) {
            _ = ctx.stream.read_byte();
            const len = skip.parse_field_pkg_length(ctx.stream);
            bit_offset += len;
        } else if (b == 0x01) {
            _ = ctx.stream.read_byte();
            _ = ctx.stream.read_byte();
            _ = ctx.stream.read_byte();
        } else if (b == 0x02) {
            _ = ctx.stream.read_byte();
            skip.skip_term_arg(ctx.stream);
        } else if (b == 0x03) {
            _ = ctx.stream.read_byte();
            _ = ctx.stream.read_byte();
            _ = ctx.stream.read_byte();
            _ = ctx.stream.read_byte();
        } else if (path_mod.is_name_lead(b)) {
            const field_name = ctx.stream.read_bytes(4) orelse break;
            const bit_width = skip.parse_field_pkg_length(ctx.stream);

            const node = ctx.ns.alloc_node(
                field_name[0..4].*,
                .index_field,
            ) catch break;
            node.object = .{
                .index_field_unit = .{
                    .index_name = index_name,
                    .data_name = data_name,
                    .bit_offset = bit_offset,
                    .bit_width = bit_width,
                    .access_type = flags.access_type,
                    .lock_rule = flags.lock_rule,
                    .update_rule = flags.update_rule,
                    .index_node = if (index_node) |n| @ptrCast(n) else null,
                    .data_node = if (data_node) |n| @ptrCast(n) else null,
                },
            };
            ctx.scope.add_child(node);
            bit_offset += bit_width;
        } else {
            break;
        }
    }
    ctx.stream.pos = @min(end_pos, ctx.stream.data.len);
}
