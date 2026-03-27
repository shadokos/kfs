/// AML MethodInvocation evaluation (ACPI 6.4 §20.2.5.4).
///
/// MethodInvocation := NameString TermArgList (§20.2.5.4)
///
/// When a NameString resolves to a .method node, the method is called:
/// 1. Evaluate arg_count TermArgs from the stream (§5.5.2.1)
/// 2. Push a new MethodFrame onto the Context stack (max depth 16)
/// 3. Execute the method's TermList
/// 4. Pop the frame and return the result (§5.5.2.3)
///
/// When it resolves to a data object (integer, string, field, etc.),
/// the object's value is returned directly without invocation.
const std = @import("std");
const path_mod = @import("../../namespace/path.zig");
const ns_mod = @import("../../namespace/namespace.zig");
const node_mod = @import("../../namespace/node.zig");
const objects = @import("../objects.zig");
const parser = @import("../parser.zig");
const context_mod = @import("../context.zig");
const field_io = @import("field_io.zig");

const Object = objects.Object;
const Namespace = ns_mod.Namespace;
const Node = node_mod.Node;
const Stream = parser.Stream;
const Error = @import("executor.zig").Error;
const EvalContext = @import("executor.zig").EvalContext;

const log = std.log.scoped(.acpi_exec);

/// Resolve a NameString from the stream and evaluate it as an operand.
/// If the target is a method, invoke it. Otherwise return its stored value.
pub fn eval_name_operand(ectx: *EvalContext) Error!Object {
    const frame = ectx.ctx.current() orelse return .uninitialized;
    const parsed = path_mod.parse(
        ectx.alloc,
        ectx.stream.data[ectx.stream.pos..],
    ) catch return Error.parse_error;
    const p = parsed orelse return Error.parse_error;
    defer p.deinit(ectx.alloc);
    ectx.stream.pos += p.bytes_consumed;

    const node = ectx.ns.resolve(frame.scope, &p) orelse {
        if (p.segments.len > 0) {
            log.debug("name not found: {s}", .{
                path_mod.format_seg(&p.segments[p.segments.len - 1]),
            });
        }
        return .uninitialized;
    };

    return eval_resolved_node(ectx, node);
}

/// Evaluate a resolved namespace node as an operand.
fn eval_resolved_node(ectx: *EvalContext, node: *Node) Error!Object {
    const frame = ectx.ctx.current() orelse return .uninitialized;

    switch (node.object) {
        .method => |method| {
            // Evaluate arguments from the stream (§5.5.2.1)
            const operand = @import("operand.zig");
            var args: [7]Object = .{.uninitialized} ** 7;
            for (0..method.arg_count) |i| {
                if (ectx.stream.eof()) break;
                args[i] = operand.eval_operand(ectx) catch .uninitialized;
            }

            // Push new frame (§5.5.2)
            if (ectx.ctx.depth >= context_mod.MAX_METHOD_DEPTH)
                return Error.stack_overflow;
            const new_frame = ectx.ctx.push_frame(
                node.parent orelse ectx.ns.root,
                method.code,
                args[0..method.arg_count],
            ) catch return Error.stack_overflow;

            // Execute method body
            return execute_method_frame(ectx, new_frame);
        },
        .integer, .string, .buffer, .package => return node.object,
        .field_unit => |fu| {
            return field_io.read_field(
                ectx.ns,
                node.parent orelse frame.scope,
                &fu,
            );
        },
        .index_field_unit => |ifu| {
            return field_io.read_index_field(ectx.ns, frame.scope, &ifu);
        },
        .buffer_field => |bf| {
            return field_io.read_buffer_field(&bf);
        },
        else => return node.object,
    }
}

/// Execute a method frame that has already been pushed.
/// Runs the TermList, pops the frame, and returns the result.
fn execute_method_frame(
    ectx: *EvalContext,
    frame: *context_mod.MethodFrame,
) Error!Object {
    const term = @import("term.zig");

    // Save and replace the current stream
    const saved_stream = ectx.stream;
    var method_stream = Stream{ .data = frame.code };
    ectx.stream = &method_stream;

    // Execute method body TermList
    var result: Object = .uninitialized;
    while (!method_stream.eof()) {
        const ret = term.eval_term(ectx) catch |err| {
            switch (err) {
                Error.parse_error => {
                    // Skip unknown byte (recovery)
                    _ = method_stream.read_byte();
                    continue;
                },
                else => {
                    frame.cleanup_dynamic_nodes();
                    ectx.stream = saved_stream;
                    _ = ectx.ctx.pop_frame();
                    return err;
                },
            }
        };

        if (ret) |obj| {
            result = obj;
            break;
        }
    }

    if (result == .uninitialized) {
        result = frame.result;
    }

    frame.cleanup_dynamic_nodes();
    ectx.stream = saved_stream;
    _ = ectx.ctx.pop_frame();
    return result;
}
