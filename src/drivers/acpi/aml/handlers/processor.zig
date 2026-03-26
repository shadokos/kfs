/// EXT_PROCESSOR_OP handler (0x5B 0x83, §20.2.5.2).
///
/// DefProcessor := ProcessorOp PkgLength NameString ProcID PblkAddr PblkLen TermList
///   ProcID   := ByteData   (processor ID, §20.2.5.2)
///   PblkAddr := DWordData  (P_BLK register block base address, §20.2.5.2)
///   PblkLen  := ByteData   (P_BLK register block length, §20.2.5.2)
///
/// ProcessorOp (0x5B 0x83) is Permanently Reserved in ACPI 6.4 (§20.3 Table 20.2):
/// the DefProcessor production no longer appears in §20.2.5.2 NamedObj encoding;
/// only the ProcID/PblkAddr/PblkLen sub-rules remain defined there.
/// Kept to parse legacy DSDT/SSDT tables. New firmware: use Device + _HID "ACPI0007" (§8.4).
const parser = @import("../parser.zig");
const opcodes = @import("../opcodes.zig");
const handlers = @import("../handlers.zig");
const common = @import("common.zig");

const Stream = parser.Stream;
const Error = handlers.Error;
const HandleContext = handlers.HandleContext;

pub const ext_opcode: u8 = opcodes.EXT_PROCESSOR_OP;

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

    const proc_id = ctx.stream.read_byte() orelse
        return Error.parse_error;
    const pblk_addr = ctx.stream.read_dword() orelse
        return Error.parse_error;
    const pblk_len = ctx.stream.read_byte() orelse
        return Error.parse_error;

    if (parsed.segments.len > 0) {
        const resolved = try common.resolve_parent(ctx.ns, ctx.scope, &parsed);

        const target = ctx.ns.alloc_node(
            resolved.name,
            .processor,
        ) catch return Error.out_of_nodes;
        target.object = .{
            .processor = .{
                .proc_id = proc_id,
                .pblk_addr = pblk_addr,
                .pblk_len = pblk_len,
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
