/// Shared utilities for AML namespace handlers.
const std = @import("std");
const path_mod = @import("../../namespace/path.zig");
const ns_mod = @import("../../namespace/namespace.zig");
const node_mod = @import("../../namespace/node.zig");
const handlers = @import("../handlers.zig");

const Namespace = ns_mod.Namespace;
const Node = node_mod.Node;
const Error = handlers.Error;

pub const ResolvedParent = struct {
    parent: *Node,
    name: path_mod.NameSeg,
};

/// Given a parsed path, resolve the parent scope and return (parent, leaf_name).
/// For a path like \_SB.PCI0.DEV, resolves \_SB.PCI0 and returns ("DEV_").
/// For a single NameSeg like "DEV", returns (scope, "DEV_").
pub fn resolve_parent(
    ns: *Namespace,
    scope: *Node,
    parsed: *const path_mod.ParsedPath,
) Error!ResolvedParent {
    if (parsed.segments.len == 0) return Error.parse_error;

    const name = parsed.segments[parsed.segments.len - 1];

    if (parsed.segments.len > 1) {
        const parent_parsed = path_mod.ParsedPath{
            .is_absolute = parsed.is_absolute,
            .parent_count = parsed.parent_count,
            .segments = parsed.segments[0 .. parsed.segments.len - 1],
            .bytes_consumed = 0,
        };
        const parent = ns.resolve_or_create(
            scope,
            &parent_parsed,
        ) catch return Error.out_of_nodes;
        return .{ .parent = parent, .name = name };
    } else {
        var start: *Node = if (parsed.is_absolute) ns.root else scope;
        for (0..parsed.parent_count) |_| {
            start = start.parent orelse ns.root;
        }
        return .{ .parent = start, .name = name };
    }
}

/// Parse a NamePath from the stream, using the context's allocator.
/// Returns null on parse failure, maps OutOfMemory to parse_error.
pub fn parse_name_path(
    alloc: std.mem.Allocator,
    data: []const u8,
) Error!?path_mod.ParsedPath {
    return path_mod.parse(alloc, data) catch return Error.out_of_nodes;
}
