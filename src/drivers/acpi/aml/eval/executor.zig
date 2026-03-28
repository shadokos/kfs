/// AML method execution engine (ACPI 6.4 §5.5, §20.2.5).
///
/// Evaluates AML bytecode for control method execution. Entry point is
/// evaluate(), which pushes a method frame, runs the TermList, and
/// returns the result object.
///
/// The evaluator is split into two levels mirroring the AML grammar:
///   - term.zig:    statement-level (TermObj, §20.2.5)   -> returns ?Object
///   - operand.zig: expression-level (TermArg, §20.2.5.4) -> returns Object
///
/// Integer results are masked to 32 bits for \_REV = 1 (§5.7.4).
const std = @import("std");
const parser = @import("../parser.zig");
const objects = @import("../objects.zig");
const context_mod = @import("../context.zig");
const ns_mod = @import("../../namespace/namespace.zig");
const node_mod = @import("../../namespace/node.zig");
const osl = @import("../../os_layer.zig");
const field_io = @import("field_io.zig");
const predefined = @import("predefined.zig");

pub const Object = objects.Object;
const Namespace = ns_mod.Namespace;
const Node = node_mod.Node;
const Context = context_mod.Context;
const Stream = parser.Stream;

const log = std.log.scoped(.acpi_exec);

pub const Error = error{
    parse_error,
    type_mismatch,
    stack_overflow,
    not_found,
    unimplemented,
    division_by_zero,
    out_of_nodes,
    path_not_found,
    invalid_path,
};

/// Evaluation context passed to all eval_* functions.
pub const EvalContext = struct {
    ns: *Namespace,
    alloc: std.mem.Allocator,
    ctx: *Context,
    stream: *Stream,
};

/// Evaluate a named object in the namespace (§5.5, §20.2.5.2).
///
/// If the node holds a method, execute it with the given args.
/// If it holds a field, read the field value.
/// Otherwise return the stored object directly.
pub fn evaluate(
    ns: *Namespace,
    node: *Node,
    args: []const Object,
) Error!Object {
    switch (node.object) {
        .method => |method| {
            // Built-in methods have empty code (§5.7)
            if (method.code.len == 0) {
                return predefined.dispatch(node, args) orelse .uninitialized;
            }

            var ctx = Context{};
            const frame = ctx.push_frame(
                node.parent orelse ns.root,
                method.code,
                args,
            ) catch return Error.stack_overflow;

            return execute_method(ns, &ctx, frame);
        },
        .field_unit => |fu| {
            return field_io.read_field(ns, node.parent orelse ns.root, &fu);
        },
        .index_field_unit => |ifu| {
            return field_io.read_index_field(ns, node.parent orelse ns.root, &ifu);
        },
        .buffer_field => |bf| {
            return field_io.read_buffer_field(&bf);
        },
        .bank_field_unit => |bfu| {
            return field_io.read_bank_field(ns, node.parent orelse ns.root, &bfu);
        },
        .integer, .string, .buffer, .package => return node.object,
        .uninitialized => return .uninitialized,
        else => return node.object,
    }
}

/// Execute a method frame and return its result (§5.5.2).
fn execute_method(
    ns: *Namespace,
    ctx: *Context,
    frame: *context_mod.MethodFrame,
) Error!Object {
    const term = @import("term.zig");
    const alloc = osl.allocator();

    var stream = Stream{ .data = frame.code };
    var ectx = EvalContext{
        .ns = ns,
        .alloc = alloc,
        .ctx = ctx,
        .stream = &stream,
    };

    while (!stream.eof()) {
        const result = term.eval_term(&ectx) catch |err| {
            switch (err) {
                Error.parse_error => {
                    _ = stream.read_byte();
                    continue;
                },
                else => {
                    frame.cleanup_dynamic_nodes();
                    _ = ctx.pop_frame();
                    return err;
                },
            }
        };

        if (result) |obj| {
            frame.result = obj;
            frame.cleanup_dynamic_nodes();
            _ = ctx.pop_frame();
            return obj;
        }
    }

    const result = frame.result;
    frame.cleanup_dynamic_nodes();
    _ = ctx.pop_frame();
    return result;
}
