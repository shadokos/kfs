/// StoreOp and Target write dispatch (ACPI 6.4 §20.2.5.4).
///
/// DefStore := StoreOp TermArg SuperName   (§20.2.5.4)
/// StoreOp  := 0x70
///
/// Target := SuperName | NullName          (§20.2.2)
/// NullName := 0x00
///
/// SuperName := SimpleName | DebugObj | ReferenceTypeOpcode (§20.2.2)
/// SimpleName := NameString | ArgObj | LocalObj             (§20.2.2)
const std = @import("std");
const opcodes = @import("../opcodes.zig");
const objects = @import("../objects.zig");
const path_mod = @import("../../namespace/path.zig");
const ns_mod = @import("../../namespace/namespace.zig");
const node_mod = @import("../../namespace/node.zig");
const skip = @import("../skip.zig");
const parser = @import("../parser.zig");
const local_arg = @import("local_arg.zig");
const debug_mod = @import("debug.zig");
const field_io = @import("field_io.zig");

const Object = objects.Object;
const Namespace = ns_mod.Namespace;
const Node = node_mod.Node;
const Stream = parser.Stream;
const Error = @import("executor.zig").Error;
const EvalContext = @import("executor.zig").EvalContext;

const log = std.log.scoped(.acpi_exec);

/// Evaluate DefStore: source TermArg, then write to SuperName target (§20.2.5.4).
/// StoreOp (0x70) must already be consumed by the caller.
pub fn eval_store(ectx: *EvalContext) Error!Object {
    const operand = @import("operand.zig");
    const val = try operand.eval_operand(ectx);
    try write_super_name(ectx, val);
    return val;
}

/// Write a value to a Target (SuperName | NullName) read from the stream (§20.2.2).
/// Used by arithmetic ops whose grammar includes a Target operand.
pub fn write_target(ectx: *EvalContext, value: Object) Error!void {
    const b = ectx.stream.peek() orelse return;
    if (b == 0x00) {
        // NullName: discard the result (§20.2.2)
        _ = ectx.stream.read_byte();
        return;
    }
    try write_super_name(ectx, value);
}

/// Public wrapper for write_super_name. Used by Increment/Decrement (§20.2.5.4)
/// which need to write back to the same SuperName they just read.
pub fn write_super_name_pub(ectx: *EvalContext, value: Object) Error!void {
    return write_super_name(ectx, value);
}

/// Write a value to a SuperName read from the stream (§20.2.2).
fn write_super_name(ectx: *EvalContext, value: Object) Error!void {
    const b = ectx.stream.peek() orelse return;
    const frame = ectx.ctx.current() orelse return;

    // Local0..Local7 (§20.2.6.2)
    if (b >= opcodes.LOCAL0 and b <= opcodes.LOCAL7) {
        _ = ectx.stream.read_byte();
        local_arg.write_local(frame, @truncate(b - opcodes.LOCAL0), value);
        return;
    }

    // Arg0..Arg6 (§20.2.6.1)
    if (b >= opcodes.ARG0 and b <= opcodes.ARG6) {
        _ = ectx.stream.read_byte();
        local_arg.write_arg(frame, @truncate(b - opcodes.ARG0), value);
        return;
    }

    // DebugObj (§20.2.6.3: ExtOpPrefix 0x31)
    if (b == opcodes.EXT_PREFIX) {
        if (ectx.stream.pos + 1 < ectx.stream.data.len and
            ectx.stream.data[ectx.stream.pos + 1] == opcodes.EXT_DEBUG_OP)
        {
            _ = ectx.stream.read_byte(); // EXT_PREFIX
            _ = ectx.stream.read_byte(); // EXT_DEBUG_OP
            debug_mod.log_debug_store(value);
            return;
        }
    }

    // IndexOp as target: write to buffer/package element (§20.2.5.4)
    if (b == opcodes.INDEX_OP) {
        try write_index_target(ectx, value);
        return;
    }

    // Named target (NameString, §20.2.2)
    if (path_mod.is_name_start(b)) {
        try write_named_target(ectx, value);
        return;
    }

    // Unknown target: skip one byte to avoid infinite loop
    _ = ectx.stream.read_byte();
}

/// Write to an Index target: DefIndex := IndexOp BuffPkgStrObj IndexValue Target (§20.2.5.4).
fn write_index_target(ectx: *EvalContext, value: Object) Error!void {
    const operand = @import("operand.zig");
    _ = ectx.stream.read_byte(); // INDEX_OP

    // Resolve the source object (buffer/package/string)
    const source_op = ectx.stream.peek() orelse return;
    var target_node: ?*Node = null;

    if (path_mod.is_name_start(source_op)) {
        const parsed = path_mod.parse(
            ectx.alloc,
            ectx.stream.data[ectx.stream.pos..],
        ) catch return;
        if (parsed) |p| {
            defer p.deinit(ectx.alloc);
            ectx.stream.pos += p.bytes_consumed;
            const frame = ectx.ctx.current() orelse return;
            target_node = ectx.ns.resolve(frame.scope, &p);
        }
    } else {
        _ = try operand.eval_operand(ectx);
    }

    const index = @as(usize, @intCast(@import("integer.zig").to_int(
        try operand.eval_operand(ectx),
    )));
    // Skip the target of Index itself
    skip.skip_target(ectx.stream);

    if (target_node) |node| {
        switch (node.object) {
            .buffer => |buf| {
                const mut_data = @constCast(buf.data);
                if (index < mut_data.len) {
                    mut_data[index] = @truncate(@import("integer.zig").to_int(value));
                }
            },
            .package => |pkg| {
                const mut_elems = @constCast(pkg.elements);
                if (index < mut_elems.len) {
                    mut_elems[index] = value;
                }
            },
            else => {},
        }
    }
}

/// Write to a named target resolved from a NameString in the stream.
fn write_named_target(ectx: *EvalContext, value: Object) Error!void {
    const frame = ectx.ctx.current() orelse return;
    const parsed = path_mod.parse(
        ectx.alloc,
        ectx.stream.data[ectx.stream.pos..],
    ) catch return;
    const p = parsed orelse return;
    defer p.deinit(ectx.alloc);
    ectx.stream.pos += p.bytes_consumed;

    const node = ectx.ns.resolve(frame.scope, &p) orelse {
        // Target not found: create dynamically (§5.5.2.3)
        if (p.segments.len > 0) {
            const name = p.segments[p.segments.len - 1];
            const parent = if (p.is_absolute) ectx.ns.root else frame.scope;
            const new_node = ectx.ns.alloc_node(name, .name) catch return;
            new_node.object = value;
            parent.add_child(new_node);
            frame.track_dynamic_node(new_node);
        }
        return;
    };

    // Dispatch to field I/O for field types
    switch (node.object) {
        .field_unit => |fu| {
            field_io.write_field(ectx.ns, frame.scope, &fu, value);
            return;
        },
        .index_field_unit => |ifu| {
            field_io.write_index_field(ectx.ns, frame.scope, &ifu, value);
            return;
        },
        .buffer_field => |bf| {
            field_io.write_buffer_field(&bf, value);
            return;
        },
        else => {},
    }

    // Direct assignment to named object
    node.object = value;
}
