pub const Namespace = @import("../namespace/namespace.zig").Namespace;
pub const Node = @import("../namespace/node.zig").Node;
pub const Object = @import("objects.zig").Object;

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

/// Stub: will be reimplemented opcode by opcode.
pub fn evaluate(
    ns: *Namespace,
    node: *Node,
    args: []const Object,
) Error!Object {
    _ = ns;
    _ = args;
    _ = node;
    return .uninitialized;
}
