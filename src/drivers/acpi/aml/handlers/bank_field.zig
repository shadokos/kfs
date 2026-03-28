/// EXT_BANK_FIELD_OP handler (0x5B 0x87, §20.2.5.2).
///
/// DefBankField := BankFieldOp PkgLength NameString NameString BankValue
///                 FieldFlags FieldList
///
/// Creates bank field unit nodes. Accessing a bank field first writes
/// BankValue to the bank register, then reads/writes the operation region.
const parser = @import("../parser.zig");
const opcodes = @import("../opcodes.zig");
const path_mod = @import("../../namespace/path.zig");
const skip = @import("../skip.zig");
const data = @import("../data.zig");
const handlers = @import("../handlers.zig");
const common = @import("common.zig");
const objects = @import("../objects.zig");

const Node = @import("../../namespace/node.zig").Node;
const Error = handlers.Error;
const HandleContext = handlers.HandleContext;

/// FieldFlags byte layout (§20.2.5.2)
const FieldFlags = packed struct(u8) {
    access_type: objects.AccessType,
    lock_rule: bool,
    update_rule: objects.UpdateRule,
    _reserved: u1 = 0,
};

pub const ext_opcode: u8 = opcodes.EXT_BANK_FIELD_OP;

pub fn handle(ctx: HandleContext) Error!void {
    const pkg = parser.decode_pkg_length(ctx.stream) orelse
        return Error.parse_error;
    const end_pos = ctx.stream.pos + pkg.body_length;

    // Region name
    const region_parsed = try common.parse_name_path(
        ctx.alloc,
        ctx.stream.data[ctx.stream.pos..],
    ) orelse {
        ctx.stream.pos = @min(end_pos, ctx.stream.data.len);
        return;
    };
    defer region_parsed.deinit(ctx.alloc);
    ctx.stream.pos += region_parsed.bytes_consumed;

    var region_name: [4]u8 = "____".*;
    if (region_parsed.segments.len > 0) {
        region_name = region_parsed.segments[region_parsed.segments.len - 1];
    }
    const resolved_region: ?*Node = ctx.ns.resolve(ctx.scope, &region_parsed);

    // Bank register name
    const bank_parsed = try common.parse_name_path(
        ctx.alloc,
        ctx.stream.data[ctx.stream.pos..],
    ) orelse {
        ctx.stream.pos = @min(end_pos, ctx.stream.data.len);
        return;
    };
    defer bank_parsed.deinit(ctx.alloc);
    ctx.stream.pos += bank_parsed.bytes_consumed;

    var bank_name: [4]u8 = "____".*;
    if (bank_parsed.segments.len > 0) {
        bank_name = bank_parsed.segments[bank_parsed.segments.len - 1];
    }
    const resolved_bank: ?*Node = ctx.ns.resolve(ctx.scope, &bank_parsed);

    // BankValue (TermArg => Integer, parsed as constant at load time)
    const bank_value = data.parse_integer_data(ctx.stream);

    // Field flags
    const flags: FieldFlags = @bitCast(ctx.stream.read_byte() orelse {
        ctx.stream.pos = @min(end_pos, ctx.stream.data.len);
        return;
    });

    // Parse FieldList (same encoding as DefField, §20.2.5.2)
    var bit_offset: u32 = 0;
    while (ctx.stream.pos < end_pos) {
        const b = ctx.stream.peek() orelse break;

        if (b == 0x00) {
            // ReservedField
            _ = ctx.stream.read_byte();
            const len = skip.parse_field_pkg_length(ctx.stream);
            bit_offset += len;
        } else if (b == 0x01) {
            // AccessField
            _ = ctx.stream.read_byte();
            _ = ctx.stream.read_byte();
            _ = ctx.stream.read_byte();
        } else if (b == 0x02) {
            // ConnectField
            _ = ctx.stream.read_byte();
            skip.skip_term_arg(ctx.stream);
        } else if (b == 0x03) {
            // ExtendedAccessField
            _ = ctx.stream.read_byte();
            _ = ctx.stream.read_byte();
            _ = ctx.stream.read_byte();
            _ = ctx.stream.read_byte();
        } else if (path_mod.is_name_lead(b)) {
            // NamedField
            const field_name = ctx.stream.read_bytes(4) orelse break;
            const bit_width = skip.parse_field_pkg_length(ctx.stream);

            const node = ctx.ns.alloc_node(
                field_name[0..4].*,
                .bank_field,
            ) catch break;
            node.object = .{
                .bank_field_unit = .{
                    .region_name = region_name,
                    .bank_name = bank_name,
                    .bank_value = bank_value,
                    .bit_offset = bit_offset,
                    .bit_width = bit_width,
                    .access_type = flags.access_type,
                    .lock_rule = flags.lock_rule,
                    .update_rule = flags.update_rule,
                    .region_node = if (resolved_region) |rn| @ptrCast(rn) else null,
                    .bank_node = if (resolved_bank) |bn| @ptrCast(bn) else null,
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
