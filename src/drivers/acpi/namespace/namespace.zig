const std = @import("std");
const colors = @import("colors");
const Node = @import("node.zig").Node;
const NodeType = @import("node.zig").NodeType;
const path_mod = @import("path.zig");
const NameSeg = path_mod.NameSeg;
const Cache = @import("../../../memory/object_allocators/slab/cache.zig").Cache;
const memory = @import("../../../memory.zig");

const log = std.log.scoped(.acpi_ns);

pub const Error = error{
    OutOfMemory,
    path_not_found,
    invalid_path,
};

pub const Namespace = struct {
    root: *Node = undefined,
    node_cache: *Cache = undefined,

    /// Initialize the namespace. Must be called before any other method.
    ///
    /// Creates the predefined root scopes (§5.3.1 Table 5.148) and
    /// predefined objects (§5.7 Table 5.174).
    pub fn init_in_place(self: *Namespace) !void {
        self.node_cache = try memory.globalCache.create(
            "acpi_node",
            memory.directPageAllocator.page_allocator(),
            @sizeOf(Node),
            @alignOf(Node),
            1,
            .{},
        );

        self.root = try self.alloc_node("\\___".*, .root);
        errdefer self.node_cache.allocator().destroy(self.root);

        // Predefined root scopes (§5.3.1 Table 5.148)
        const scopes = [_][4]u8{
            "_SB_".*, "_GPE".*, "_TZ_".*, "_PR_".*, "_SI_".*,
        };
        // TODO: free any previously allocated nodes if an allocation fails during this loop
        for (scopes) |name| {
            // TODO: handle allocation failures here instead of just skipping the scope
            const node = self.alloc_node(name, .scope) catch continue;
            self.root.add_child(node);
        }

        // Predefined objects (§5.7 Table 5.174)

        // \_GL: Global Lock mutex (§5.7.1)
        const gl_node = try self.alloc_node("_GL_".*, .mutex);
        errdefer self.node_cache.allocator().destroy(gl_node);
        self.root.add_child(gl_node);

        // \_OS: OS name string (§5.7.3)
        const os_node = try self.alloc_node("_OS_".*, .name);
        errdefer self.node_cache.allocator().destroy(os_node);
        // TODO: os_node.object = .{ .string = "ShadokOS" };
        self.root.add_child(os_node);

        // \_OSI: OS interface method (§5.7.2)
        const osi_node = try self.alloc_node("_OSI".*, .method);
        errdefer self.node_cache.allocator().destroy(osi_node);
        // TODO: implement _OSI method logic
        self.root.add_child(osi_node);

        // \_REV: ACPI revision supported (§5.7.4)
        // Value 1 = "only ACPI 1 supported, only 32-bit integers" (§5.7.4).
        // This kernel is 32-bit, so integers are 32-bit only per §5.7.4.
        const rev_node = try self.alloc_node("_REV".*, .name);
        errdefer self.node_cache.allocator().destroy(rev_node);
        // TODO: rev_node.object = .{ .integer = 1 };
        self.root.add_child(rev_node);
    }

    fn alloc_node_internal(self: *Namespace) Error!*Node {
        const node = self.node_cache.allocator().create(Node) catch return Error.OutOfMemory;
        node.* = .{
            .name = "____".*,
            .node_type = .scope,
        };
        return node;
    }

    /// Allocate a new namespace node.
    pub fn alloc_node(
        self: *Namespace,
        name: NameSeg,
        node_type: NodeType,
    ) Error!*Node {
        const node = try self.alloc_node_internal();
        node.* = .{
            .name = name,
            .node_type = node_type,
        };
        return node;
    }

    /// Resolve a parsed path from a given scope.
    ///
    /// Name resolution rules (§5.3):
    /// - Absolute paths ('\' prefix): always resolved from root.
    /// - Parent-prefix paths ('^' prefix): ascend the given number of levels.
    /// - Single NameSeg with no prefixes: upward search from current scope.
    /// - Multi-segment paths: walk down from the anchor scope, no upward search.
    pub fn resolve(
        self: *Namespace,
        scope: *Node,
        parsed: *const path_mod.ParsedPath,
    ) ?*Node {
        var current: *Node = if (parsed.is_absolute)
            self.root
        else
            scope;

        for (0..parsed.parent_count) |_| {
            current = current.parent orelse self.root;
        }

        // §5.3: single NameSeg with no prefixes triggers upward search
        if (!parsed.is_absolute and parsed.parent_count == 0 and parsed.segments.len == 1) {
            var search_scope: ?*Node = current;
            const single_seg = parsed.segments[0];
            while (search_scope) |node| {
                if (node.find_child(single_seg)) |child| {
                    return child;
                }
                search_scope = node.parent;
            }
            return self.root.find_child(single_seg);
        }

        for (parsed.segments) |seg| {
            if (current.find_child(seg)) |child| {
                current = child;
            } else {
                return null;
            }
        }

        return current;
    }

    /// Resolve a single 4-char NameSeg starting from the given scope,
    /// using ACPI §5.3 upward search rules.
    /// Searches upward through parent chain, then falls back to root.
    pub fn resolve_name(
        self: *Namespace,
        scope: *Node,
        name: path_mod.NameSeg,
    ) ?*Node {
        var current: ?*Node = scope;
        while (current) |node| {
            if (node.find_child(name)) |child| {
                return child;
            }
            current = node.parent;
        }
        // Final fallback: check root directly
        return self.root.find_child(name);
    }

    /// Resolve or create intermediate scopes for a path.
    pub fn resolve_or_create(
        self: *Namespace,
        scope: *Node,
        parsed: *const path_mod.ParsedPath,
    ) Error!*Node {
        var current: *Node = if (parsed.is_absolute)
            self.root
        else
            scope;

        for (0..parsed.parent_count) |_| {
            current = current.parent orelse self.root;
        }

        for (parsed.segments) |seg| {
            if (current.find_child(seg)) |child| {
                current = child;
            } else {
                const node = try self.alloc_node(seg, .scope);
                current.add_child(node);
                current = node;
            }
        }

        return current;
    }

    /// Resolve a path string like "\\_SB.PCI0._STA".
    pub fn resolve_path(
        self: *Namespace,
        path_str: []const u8,
    ) ?*Node {
        var current = self.root;

        var iter = std.mem.splitScalar(u8, path_str, '.');
        var first = true;
        while (iter.next()) |segment| {
            var seg = segment;
            if (first) {
                first = false;
                if (seg.len > 0 and seg[0] == '\\') {
                    seg = seg[1..];
                    current = self.root;
                }
            }
            if (seg.len == 0) continue;

            // Skip root-name padding (e.g. "___" from "\___._SB_")
            if (current == self.root) {
                var all_underscores = true;
                for (seg) |c| {
                    if (c != '_') {
                        all_underscores = false;
                        break;
                    }
                }
                if (all_underscores) continue;
            }

            var name: NameSeg = "____".*;
            const copy_len = @min(seg.len, 4);
            @memcpy(name[0..copy_len], seg[0..copy_len]);

            if (current.find_child(name)) |child| {
                current = child;
            } else {
                return null;
            }
        }

        return current;
    }

    /// Dump the namespace tree for debugging.
    pub fn dump(self: *const Namespace) void {
        log.info("Namespace tree:", .{});
        dump_node(self.root, 0);
    }

    fn dump_node(node: *const Node, depth: usize) void {
        if (depth > 20) return;

        var indent_buf: [80]u8 = undefined;
        const indent_len = @min(depth * 2, indent_buf.len);
        @memset(indent_buf[0..indent_len], ' ');

        const type_str = @tagName(node.node_type);
        const name = path_mod.format_seg(&node.name);

        log.debug("{s}{s}{s}{s} [{s}]", .{
            indent_buf[0..indent_len],
            colors.magenta,
            name,
            colors.reset,
            type_str,
        });

        var child = node.first_child;
        while (child) |c| {
            dump_node(c, depth + 1);
            child = c.next_sibling;
        }
    }
};
