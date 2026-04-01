/// AML term (statement-level) evaluation dispatcher (ACPI 6.4 §20.2.5).
///
/// Evaluates a single TermObj from the stream. Returns:
/// - null: statement executed normally, continue to next term
/// - Object: a Return value that must propagate up the call stack
///
/// This is the statement-level counterpart to operand.zig's expression-level
/// eval_operand(). The split mirrors the AML grammar (§20.2.5):
///   TermObj := NameSpaceModifierObj | NamedObj | StatementOpcode | ExpressionOpcode
const std = @import("std");
const opcodes = @import("../opcodes.zig");
const objects = @import("../objects.zig");
const parser = @import("../parser.zig");
const skip = @import("../skip.zig");
const path_mod = @import("../../namespace/path.zig");

const control = @import("control.zig");
const operand = @import("operand.zig");
const integer = @import("integer.zig");
const osl = @import("../../os_layer.zig");

const Object = objects.Object;
const Error = @import("executor.zig").Error;
const EvalContext = @import("executor.zig").EvalContext;

const log = std.log.scoped(.acpi_exec);

/// Evaluate a single term from the stream.
/// Returns non-null Object on Return; null to continue execution.
pub fn eval_term(ectx: *EvalContext) Error!?Object {
    const op = ectx.stream.peek() orelse return null;
    const frame = ectx.ctx.current() orelse return null;

    switch (op) {
        // -- DefReturn (§20.2.5.3) --
        opcodes.RETURN_OP => {
            _ = ectx.stream.read_byte();
            return try control.eval_return(ectx);
        },

        // -- DefStore (§20.2.5.4) --
        opcodes.STORE_OP => {
            _ = ectx.stream.read_byte();
            const store = @import("store.zig");
            _ = try store.eval_store(ectx);
            return null;
        },

        // -- DefIfElse (§20.2.5.3) --
        opcodes.IF_OP => {
            _ = ectx.stream.read_byte();
            return control.eval_if_else(ectx);
        },

        // -- DefWhile (§20.2.5.3) --
        opcodes.WHILE_OP => {
            _ = ectx.stream.read_byte();
            return control.eval_while(ectx);
        },

        // -- DefBreak (§20.2.5.3) --
        opcodes.BREAK_OP => {
            _ = ectx.stream.read_byte();
            return control.eval_break(ectx);
        },

        // -- DefContinue (§20.2.5.3) --
        opcodes.CONTINUE_OP => {
            _ = ectx.stream.read_byte();
            _ = try control.eval_continue(ectx);
            return null;
        },

        // -- DefNoop (§20.2.5.3) --
        opcodes.NOOP_OP => {
            _ = ectx.stream.read_byte();
            return null;
        },

        // -- DefBreakPoint (§20.2.5.3) --
        opcodes.BREAK_POINT_OP => {
            _ = ectx.stream.read_byte();
            return null;
        },

        // -- DefNotify (§20.2.5.3): NotifyOp NotifyObject NotifyValue --
        opcodes.NOTIFY_OP => {
            _ = ectx.stream.read_byte();
            const target_node = resolve_notify_object(ectx);
            const val = integer.to_int(try operand.eval_operand(ectx));
            if (target_node) |node| {
                @import("../../events.zig").dispatch_notify(ectx.ns, node, val);
            } else {
                log.debug("Notify: value={d} (unresolved target)", .{val});
            }
            return null;
        },

        // -- DefName during execution (§20.2.5.1): create dynamic named object --
        opcodes.NAME_OP => {
            _ = ectx.stream.read_byte();
            try eval_runtime_name(ectx, frame);
            return null;
        },

        // -- DefAlias during execution (§20.2.5.1): create dynamic alias --
        opcodes.ALIAS_OP => {
            _ = ectx.stream.read_byte();
            try eval_runtime_alias(ectx, frame);
            return null;
        },

        // -- Structural opcodes that should be skipped during execution --
        opcodes.SCOPE_OP, opcodes.METHOD_OP => {
            _ = ectx.stream.read_byte();
            skip.skip_pkg_length(ectx.stream);
            return null;
        },

        // -- CreateXxxField: buffer field creation during execution (§20.2.5.2) --
        opcodes.CREATE_DWORD_FIELD_OP,
        opcodes.CREATE_WORD_FIELD_OP,
        opcodes.CREATE_BYTE_FIELD_OP,
        opcodes.CREATE_BIT_FIELD_OP,
        opcodes.CREATE_QWORD_FIELD_OP,
        => {
            try eval_create_field(ectx, frame);
            return null;
        },

        // -- Extended prefix: statement-level extended opcodes --
        opcodes.EXT_PREFIX => {
            return eval_ext_term(ectx, frame);
        },

        // -- Everything else: delegate to operand evaluator --
        else => {
            const val = try operand.eval_operand(ectx);
            frame.result = val;
            return null;
        },
    }
}

/// Handle DefName at runtime: create a dynamic namespace object (§5.5.2.3).
fn eval_runtime_name(
    ectx: *EvalContext,
    frame: *@import("../context.zig").MethodFrame,
) Error!void {
    const parsed = path_mod.parse(
        ectx.alloc,
        ectx.stream.data[ectx.stream.pos..],
    ) catch return Error.parse_error;
    const p = parsed orelse return Error.parse_error;
    defer p.deinit(ectx.alloc);
    ectx.stream.pos += p.bytes_consumed;

    const val = try operand.eval_operand(ectx);

    if (p.segments.len > 0) {
        const name = p.segments[p.segments.len - 1];
        const parent = if (p.is_absolute) ectx.ns.root else frame.scope;
        if (parent.find_child(name)) |existing| {
            existing.object = val;
        } else {
            const node = ectx.ns.alloc_node(name, .name) catch return;
            node.object = val;
            parent.add_child(node);
            frame.track_dynamic_node(node);
        }
    }
}

/// Handle DefAlias at runtime: create a dynamic alias node (§20.2.5.1).
fn eval_runtime_alias(
    ectx: *EvalContext,
    frame: *@import("../context.zig").MethodFrame,
) Error!void {
    // Source name
    const source_parsed = path_mod.parse(
        ectx.alloc,
        ectx.stream.data[ectx.stream.pos..],
    ) catch return Error.parse_error;
    const sp = source_parsed orelse return Error.parse_error;
    defer sp.deinit(ectx.alloc);
    ectx.stream.pos += sp.bytes_consumed;

    // Alias name
    const alias_parsed = path_mod.parse(
        ectx.alloc,
        ectx.stream.data[ectx.stream.pos..],
    ) catch return Error.parse_error;
    const ap = alias_parsed orelse return Error.parse_error;
    defer ap.deinit(ectx.alloc);
    ectx.stream.pos += ap.bytes_consumed;

    // Resolve source
    const source_node = ectx.ns.resolve(frame.scope, &sp) orelse return;

    // Create alias
    if (ap.segments.len > 0) {
        const name = ap.segments[ap.segments.len - 1];
        const parent = if (ap.is_absolute) ectx.ns.root else frame.scope;
        if (parent.find_child(name)) |existing| {
            existing.object = source_node.object;
        } else {
            const node = ectx.ns.alloc_node(name, source_node.node_type) catch return;
            node.object = source_node.object;
            parent.add_child(node);
            frame.track_dynamic_node(node);
        }
    }
}

/// Handle CreateXxxField opcodes at runtime (§20.2.5.2).
fn eval_create_field(
    ectx: *EvalContext,
    frame: *@import("../context.zig").MethodFrame,
) Error!void {
    const field_op = ectx.stream.read_byte() orelse return Error.parse_error;

    // Source buffer (TermArg that must resolve to a node)
    const source_op = ectx.stream.peek() orelse return Error.parse_error;
    var source_node: ?*@import("../../namespace/node.zig").Node = null;

    if (path_mod.is_name_start(source_op)) {
        const parsed = path_mod.parse(
            ectx.alloc,
            ectx.stream.data[ectx.stream.pos..],
        ) catch return Error.parse_error;
        if (parsed) |p| {
            defer p.deinit(ectx.alloc);
            ectx.stream.pos += p.bytes_consumed;
            source_node = ectx.ns.resolve(frame.scope, &p);
        }
    } else {
        _ = try operand.eval_operand(ectx);
    }

    // Index value (byte index for most, bit index for CreateBitField)
    const index_val = integer.to_int(try operand.eval_operand(ectx));

    // Field name
    const name_parsed = path_mod.parse(
        ectx.alloc,
        ectx.stream.data[ectx.stream.pos..],
    ) catch return Error.parse_error;
    const np = name_parsed orelse return Error.parse_error;
    defer np.deinit(ectx.alloc);
    ectx.stream.pos += np.bytes_consumed;

    const bit_offset: u32 = switch (field_op) {
        opcodes.CREATE_BIT_FIELD_OP => @truncate(index_val),
        else => @as(u32, @truncate(index_val)) * 8,
    };
    const bit_width: u32 = switch (field_op) {
        opcodes.CREATE_BIT_FIELD_OP => 1,
        opcodes.CREATE_BYTE_FIELD_OP => 8,
        opcodes.CREATE_WORD_FIELD_OP => 16,
        opcodes.CREATE_DWORD_FIELD_OP => 32,
        opcodes.CREATE_QWORD_FIELD_OP => 64,
        else => unreachable,
    };

    if (source_node) |src| {
        if (np.segments.len > 0) {
            const name = np.segments[np.segments.len - 1];
            const parent = frame.scope;
            if (parent.find_child(name)) |existing| {
                existing.object = .{ .buffer_field = .{
                    .source_node = src,
                    .bit_offset = bit_offset,
                    .bit_width = bit_width,
                } };
            } else {
                const node = ectx.ns.alloc_node(name, .field) catch return;
                node.object = .{ .buffer_field = .{
                    .source_node = src,
                    .bit_offset = bit_offset,
                    .bit_width = bit_width,
                } };
                parent.add_child(node);
                frame.track_dynamic_node(node);
            }
        }
    }
}

/// Dispatch extended (0x5B XX) statement-level opcodes.
fn eval_ext_term(
    ectx: *EvalContext,
    frame: *@import("../context.zig").MethodFrame,
) Error!?Object {
    const saved = ectx.stream.pos;
    _ = ectx.stream.read_byte(); // EXT_PREFIX
    const ext = ectx.stream.peek() orelse return Error.parse_error;

    switch (ext) {
        // DefAcquire (§20.2.5.4): single-threaded, always succeeds
        opcodes.EXT_ACQUIRE_OP => {
            _ = ectx.stream.read_byte();
            skip.skip_super_name(ectx.stream);
            _ = ectx.stream.read_word(); // Timeout
            frame.result = .{ .integer = 0 };
            return null;
        },

        // DefRelease (§20.2.5.3)
        opcodes.EXT_RELEASE_OP => {
            _ = ectx.stream.read_byte();
            skip.skip_super_name(ectx.stream);
            return null;
        },

        // DefSleep (§20.2.5.3): SleepOp MsecTime
        opcodes.EXT_SLEEP_OP => {
            _ = ectx.stream.read_byte();
            const ms = integer.to_int(try operand.eval_operand(ectx));
            osl.stall_ms(ms);
            return null;
        },

        // DefStall (§20.2.5.3): StallOp UsecTime
        opcodes.EXT_STALL_OP => {
            _ = ectx.stream.read_byte();
            const us = integer.to_int(try operand.eval_operand(ectx));
            osl.stall_us(us);
            return null;
        },

        // DefSignal / DefReset (§20.2.5.3)
        opcodes.EXT_SIGNAL_OP, opcodes.EXT_RESET_OP => {
            _ = ectx.stream.read_byte();
            skip.skip_super_name(ectx.stream);
            return null;
        },

        // DefFatal (§20.2.5.3): FatalOp FatalType FatalCode FatalArg
        opcodes.EXT_FATAL_OP => {
            _ = ectx.stream.read_byte();
            const fatal_type = ectx.stream.read_byte() orelse 0;
            const fatal_code = ectx.stream.read_dword() orelse 0;
            const fatal_arg = integer.to_int(try operand.eval_operand(ectx));
            log.err("AML Fatal: type={d} code=0x{x} arg=0x{x}", .{
                fatal_type, fatal_code, fatal_arg,
            });
            return null;
        },

        // DefOpRegion at runtime (§20.2.5.2)
        opcodes.EXT_OP_REGION_OP => {
            _ = ectx.stream.read_byte();
            try eval_runtime_op_region(ectx, frame);
            return null;
        },

        // DefCreateField (§20.2.5.2): SourceBuff BitIndex NumBits NameString
        opcodes.EXT_CREATE_FIELD_OP => {
            _ = ectx.stream.read_byte();
            try eval_runtime_create_field(ectx, frame);
            return null;
        },

        // DebugObj (§20.2.6.3)
        opcodes.EXT_DEBUG_OP => {
            _ = ectx.stream.read_byte();
            return null;
        },

        // RevisionOp (§20.2.3)
        opcodes.EXT_REVISION_OP => {
            _ = ectx.stream.read_byte();
            frame.result = .{ .integer = 1 };
            return null;
        },

        else => {
            // Restore position and skip the unknown extended opcode
            ectx.stream.pos = saved;
            skip.skip_term_arg(ectx.stream);
            return null;
        },
    }
}

/// Handle DefOpRegion at runtime (§20.2.5.2).
fn eval_runtime_op_region(
    ectx: *EvalContext,
    frame: *@import("../context.zig").MethodFrame,
) Error!void {
    const parsed = path_mod.parse(
        ectx.alloc,
        ectx.stream.data[ectx.stream.pos..],
    ) catch return Error.parse_error;
    const p = parsed orelse return Error.parse_error;
    defer p.deinit(ectx.alloc);
    ectx.stream.pos += p.bytes_consumed;

    const space_byte = ectx.stream.read_byte() orelse return Error.parse_error;
    const offset_val = integer.to_int(try operand.eval_operand(ectx));
    const length_val = integer.to_int(try operand.eval_operand(ectx));

    if (p.segments.len > 0) {
        const rname = p.segments[p.segments.len - 1];
        const parent = if (p.is_absolute) ectx.ns.root else frame.scope;
        const obj: Object = .{
            .op_region = .{
                .space = @enumFromInt(space_byte),
                .offset = offset_val,
                .length = length_val,
            },
        };
        if (parent.find_child(rname)) |existing| {
            existing.object = obj;
        } else {
            const node = ectx.ns.alloc_node(rname, .op_region) catch return;
            node.object = obj;
            parent.add_child(node);
            frame.track_dynamic_node(node);
        }
    }
}

/// Handle DefCreateField (ExtOpPrefix 0x13) at runtime (§20.2.5.2).
fn eval_runtime_create_field(
    ectx: *EvalContext,
    frame: *@import("../context.zig").MethodFrame,
) Error!void {
    const Node = @import("../../namespace/node.zig").Node;

    // SourceBuff
    const src_op = ectx.stream.peek() orelse return Error.parse_error;
    var source_node: ?*Node = null;
    if (path_mod.is_name_start(src_op)) {
        const parsed = path_mod.parse(
            ectx.alloc,
            ectx.stream.data[ectx.stream.pos..],
        ) catch return Error.parse_error;
        if (parsed) |p| {
            defer p.deinit(ectx.alloc);
            ectx.stream.pos += p.bytes_consumed;
            source_node = ectx.ns.resolve(frame.scope, &p);
        }
    } else {
        _ = try operand.eval_operand(ectx);
    }

    // BitIndex, NumBits
    const bit_idx = @as(u32, @truncate(integer.to_int(try operand.eval_operand(ectx))));
    const num_bits = @as(u32, @truncate(integer.to_int(try operand.eval_operand(ectx))));

    // NameString
    const np_parsed = path_mod.parse(
        ectx.alloc,
        ectx.stream.data[ectx.stream.pos..],
    ) catch return Error.parse_error;
    const np = np_parsed orelse return Error.parse_error;
    defer np.deinit(ectx.alloc);
    ectx.stream.pos += np.bytes_consumed;

    if (source_node) |src| {
        if (np.segments.len > 0) {
            const name = np.segments[np.segments.len - 1];
            const parent = frame.scope;
            if (parent.find_child(name)) |existing| {
                existing.object = .{ .buffer_field = .{
                    .source_node = src,
                    .bit_offset = bit_idx,
                    .bit_width = num_bits,
                } };
            } else {
                const node = ectx.ns.alloc_node(name, .field) catch return;
                node.object = .{ .buffer_field = .{
                    .source_node = src,
                    .bit_offset = bit_idx,
                    .bit_width = num_bits,
                } };
                parent.add_child(node);
                frame.track_dynamic_node(node);
            }
        }
    }
}

/// Resolve a NotifyObject (SuperName) to a namespace Node without
/// evaluating it as an operand. NotifyObject := SuperName => Device |
/// ThermalZone | Processor (§20.2.5.3).
fn resolve_notify_object(ectx: *EvalContext) ?*@import("../../namespace/node.zig").Node {
    const b = ectx.stream.peek() orelse return null;
    const frame = ectx.ctx.current() orelse return null;

    // LocalObj / ArgObj: evaluate operand, but we can't get a node from these
    if ((b >= opcodes.LOCAL0 and b <= opcodes.LOCAL7) or
        (b >= opcodes.ARG0 and b <= opcodes.ARG6))
    {
        _ = operand.eval_operand(ectx) catch {};
        return null;
    }

    // NameString: resolve to a node in the namespace
    if (path_mod.is_name_start(b)) {
        const parsed = path_mod.parse(
            ectx.alloc,
            ectx.stream.data[ectx.stream.pos..],
        ) catch return null;
        const p = parsed orelse return null;
        defer p.deinit(ectx.alloc);
        ectx.stream.pos += p.bytes_consumed;
        return ectx.ns.resolve(frame.scope, &p);
    }

    // Fallback: evaluate as operand (won't give us a node)
    _ = operand.eval_operand(ectx) catch {};
    return null;
}
