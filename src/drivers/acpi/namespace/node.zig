const std = @import("std");
const path_mod = @import("path.zig");
const objects = @import("../aml/objects.zig");
const log = std.log.scoped(.acpi_ns);

pub const Object = objects.Object;

pub const NameSeg = path_mod.NameSeg;

/// Types of nodes that can appear in the ACPI namespace (§5.3).
/// Opcodes referenced are from §20.3 Table 20.2.
pub const NodeType = enum {
    root, // Synthetic root node (\)
    scope, // DefScope (0x10)
    device, // DefDevice (0x5B 0x82)
    method, // DefMethod (0x14)
    name, // DefName (0x08)
    field, // DefField (0x5B 0x81)
    index_field, // DefIndexField (0x5B 0x86)
    op_region, // DefOpRegion (0x5B 0x80)
    thermal_zone, // DefThermalZone (0x5B 0x85)
    /// DefProcessor (0x5B 0x83).
    /// DEPRECATED: permanently reserved in ACPI 6.4 (§20.3 Table 20.2).
    /// Use device nodes with _HID "ACPI0007" instead.
    processor,
    power_resource, // DefPowerRes (0x5B 0x84)
    mutex, // DefMutex (0x5B 0x01)
    event, // DefEvent (0x5B 0x02)
    bank_field, // DefBankField (0x5B 0x87)
};

pub const Node = struct {
    name: NameSeg,
    node_type: NodeType,
    parent: ?*Node = null,
    first_child: ?*Node = null,
    next_sibling: ?*Node = null,
    /// AML data object stored at this namespace node.
    /// Populated during DSDT/SSDT loading (DefName, DefMethod, DefField, etc.).
    /// Initially uninitialized; type depends on the node's defining opcode.
    object: Object = .uninitialized,

    /// Find a direct child by name.
    pub fn find_child(self: *const Node, name: NameSeg) ?*Node {
        var child = self.first_child;
        while (child) |c| {
            if (std.mem.eql(u8, &c.name, &name)) return c;
            child = c.next_sibling;
        }
        return null;
    }

    /// Add a child node (prepend to linked list).
    pub fn add_child(self: *Node, child: *Node) void {
        child.parent = self;
        child.next_sibling = self.first_child;
        self.first_child = child;
    }

    /// Get the full path of this node (for debugging).
    pub fn full_path(self: *const Node, buf: []u8) ![]const u8 {
        var ancestors: [64]*const Node = undefined;
        var depth: usize = 0;

        // Traversal up the tree to collect ancestors, with a safety check for maximum depth
        var current: ?*const Node = self;
        while (current) |c| : (current = c.parent) {
            if (depth >= ancestors.len) return error.PathTooDeep;
            ancestors[depth] = c;
            depth += 1;
        }

        // Inverse the slice to simplify reading from root to leaf
        const path_nodes = ancestors[0..depth];
        std.mem.reverse(*const Node, path_nodes);

        // Use a fixed buffer stream to safely write the path into the provided buffer
        var fbs = std.io.fixedBufferStream(buf);
        const writer = fbs.writer();

        var need_dot = false;
        for (path_nodes) |n| {
            if (n.node_type == .root) {
                try writer.writeByte('\\');
                need_dot = false;
                continue;
            }

            if (need_dot) {
                try writer.writeByte('.');
            }

            const trimmed = path_mod.format_seg(&n.name);
            try writer.writeAll(trimmed);
            need_dot = true;
        }

        return fbs.getWritten();
    }

    /// Count direct children.
    pub fn child_count(self: *const Node) usize {
        var count: usize = 0;
        var child = self.first_child;
        while (child) |c| {
            count += 1;
            child = c.next_sibling;
        }
        return count;
    }

    pub fn remove_child(self: *Node, child: *Node) void {
        if (self.first_child == child) {
            self.first_child = child.next_sibling;
            child.parent = null;
            child.next_sibling = null;
            return;
        }
        var prev: ?*Node = self.first_child;
        while (prev) |p| {
            if (p.next_sibling == child) {
                p.next_sibling = child.next_sibling;
                child.parent = null;
                child.next_sibling = null;
                return;
            }
            prev = p.next_sibling;
        }
    }
};
