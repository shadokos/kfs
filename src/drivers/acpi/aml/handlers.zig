/// AML opcode handler dispatch framework.
///
/// Uses comptime iteration to build dispatch tables from handler modules.
/// Each handler module exports:
///   - `pub const opcode: u8` or `pub const ext_opcode: u8` : the opcode byte
///   - `pub fn handle(ctx: HandleContext) Error!void` : the handler function
///
/// Adding a new handler: create a file in handlers/, then add it to the
/// appropriate tuple below (handler_modules or ext_handler_modules).
const std = @import("std");
const ns_mod = @import("../namespace/namespace.zig");
const node_mod = @import("../namespace/node.zig");
const parser = @import("parser.zig");

const Namespace = ns_mod.Namespace;
const Node = node_mod.Node;
const Stream = parser.Stream;

pub const Error = error{
    parse_error,
    out_of_nodes,
    path_not_found,
    invalid_path,
};

/// Context passed to every opcode handler.
pub const HandleContext = struct {
    ns: *Namespace,
    scope: *Node,
    stream: *Stream,
    /// Allocator for path segment parsing (from osl.allocator / kmalloc).
    alloc: std.mem.Allocator,
    /// Callback for recursive term list parsing.
    /// Set by aml.zig to break the circular dependency.
    parse_term_list: *const fn (*Namespace, *Node, *Stream) void,
};

// -- Simple opcode handlers (single-byte opcodes) -------------------------

const handler_modules = .{
    @import("handlers/scope.zig"),
    @import("handlers/name.zig"),
    @import("handlers/method.zig"),
    @import("handlers/external.zig"),
};

// -- Extended opcode handlers (EXT_PREFIX 0x5B + second byte) ---------------

const ext_handler_modules = .{
    @import("handlers/device.zig"),
    @import("handlers/op_region.zig"),
    @import("handlers/field.zig"),
    @import("handlers/index_field.zig"),
    @import("handlers/processor.zig"),
    @import("handlers/thermal_zone.zig"),
    @import("handlers/power_resource.zig"),
    @import("handlers/mutex.zig"),
};

/// Try to dispatch a simple (single-byte) opcode.
/// Returns true if a handler was found and executed; false otherwise.
/// The opcode byte has NOT been consumed yet; the handler must consume it.
pub fn dispatch(op: u8, ctx: HandleContext) Error!bool {
    inline for (handler_modules) |module| {
        if (op == module.opcode) {
            try module.handle(ctx);
            return true;
        }
    }
    return false;
}

/// Try to dispatch an extended opcode (second byte after EXT_PREFIX).
/// The EXT_PREFIX and ext_op bytes have already been consumed by the caller.
/// Returns true if a handler was found and executed; false otherwise.
pub fn dispatch_ext(ext_op: u8, ctx: HandleContext) Error!bool {
    inline for (ext_handler_modules) |module| {
        if (ext_op == module.ext_opcode) {
            try module.handle(ctx);
            return true;
        }
    }
    return false;
}
