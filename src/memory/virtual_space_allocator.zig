const ft = @import("../ft/ft.zig");
const paging = @import("paging.zig");
const Cache = @import("object_allocators/slab/cache.zig").Cache;
const globalCache = &@import("../memory.zig").globalCache;

/// allocator for virtual address space
/// this algorithm store free chunks of space using two AVLs (one for sizes and one for addresses)
/// so the chunks can be found by their keys or by their addresses.
/// this allows fast allocation and deallocation (O(log(n)) where n is the number of independent free chunks)
pub const VirtualSpaceAllocator = struct {
    /// roots of the trees
    tree: [2]?*Node = .{ null, null },

    /// space currently used (this field is only used for stats)
    used_space: usize = 0,

    /// the two key of the AVLs
    const AVL_type = enum(u1) { Size, Address };

    /// Node structure used in the AVLs
    const Node = struct {
        /// two hdr for the two avl keys/field
        avl: [2]AVL_hdr = .{ .{}, .{} },
        /// field used to store the nodes in the free nodes list
        next: ?*@This() = null,

        const AVL_hdr = struct {
            /// left node
            l: ?*Node = null,
            /// right node
            r: ?*Node = null,
            /// parent node
            p: ?*Node = null,
            /// balance factor used by the avl algorithm
            balance_factor: i8 = 0,
            /// value of this field
            value: usize = undefined,
        };
        pub var cache: *Cache = undefined;
        pub fn init_cache() !void {
            cache = try globalCache.create(
                "virtual_space_nodes",
                @import("../memory.zig").directPageAllocator.page_allocator(),
                @sizeOf(@This()),
                4,
            );
        }
    };

    const Self = @This();

    pub const Error = error{ NoSpaceFound, DoubleFree };

    pub fn global_init() !void {
        try Node.init_cache();
    }

    pub fn clone(self: Self) !Self {
        var ret = self;
        if (ret.tree[0]) |t| {
            ret.tree[0] = try self.clone_node(t.*);
            ret.tree[1] = null;
            ret.add_tree(t, @enumFromInt(1));
        }
        return ret;
    }

    fn add_tree(self: *Self, tree: *Node, field: AVL_type) void {
        self.add_to_tree(tree, field);
        if (tree.avl[@intFromEnum(field)].l) |l| {
            self.add_tree(l, field);
        }
        if (tree.avl[@intFromEnum(field)].r) |r| {
            self.add_tree(r, field);
        }
    }

    fn clone_node(self: Self, n: Node) !*Node {
        const ret = try alloc_node();
        ret.* = n;
        ret.avl[1].l = null;
        ret.avl[1].r = null;
        ret.avl[1].p = null;
        ret.avl[1].balance_factor = 0;
        if (ret.avl[0].l) |*l| {
            l.* = try self.clone_node(l.*.*);
            l.*.avl[0].p = ret;
        }
        if (ret.avl[0].r) |*r| {
            r.* = try self.clone_node(r.*.*);
            r.*.avl[0].p = ret;
        }
        return ret;
    }

    pub fn set_allocator(self: *Self, new_allocator: ft.mem.Allocator) void {
        self.allocator = new_allocator;
    }

    /// alloc space of size size
    pub fn alloc_space(self: *Self, size: usize) Error!usize {
        var current_node: ?*Node = self.tree[@intFromEnum(AVL_type.Size)];
        var best_fit: ?*Node = null;

        while (current_node) |n| {
            if (n.avl[@intFromEnum(AVL_type.Size)].value > size) {
                best_fit = n;
                current_node = n.avl[@intFromEnum(AVL_type.Size)].l;
            } else if (n.avl[@intFromEnum(AVL_type.Size)].value < size) {
                current_node = n.avl[@intFromEnum(AVL_type.Size)].r;
            } else {
                best_fit = n;
                break;
            }
        }
        if (best_fit) |n| {
            self.used_space += size;
            if (n.avl[@intFromEnum(AVL_type.Size)].value == size) {
                const ret = n.avl[@intFromEnum(AVL_type.Address)].value;
                self.remove_from_tree(n, AVL_type.Size);
                self.remove_from_tree(n, AVL_type.Address);
                free_node(n);
                return ret;
            } else {
                const ret = n.avl[@intFromEnum(AVL_type.Address)].value +
                    n.avl[@intFromEnum(AVL_type.Size)].value - size;
                self.remove_from_tree(n, AVL_type.Size);
                n.avl[@intFromEnum(AVL_type.Size)].value -= size;
                self.add_to_tree(n, AVL_type.Size);
                return ret;
            }
        } else return Error.NoSpaceFound;
    }

    /// set the chunk of size size at address as used space
    pub fn set_used(self: *Self, address: usize, size: usize) !void {
        var current_node: ?*Node = self.tree[@intFromEnum(AVL_type.Address)];

        while (current_node) |n| {
            if (n.avl[@intFromEnum(AVL_type.Address)].value > address) {
                current_node = n.avl[@intFromEnum(AVL_type.Address)].l;
            } else if (n.avl[@intFromEnum(AVL_type.Address)].value +
                n.avl[@intFromEnum(AVL_type.Size)].value < address)
            {
                current_node = n.avl[@intFromEnum(AVL_type.Address)].r;
            } else break;
        }
        if (current_node) |n| {
            if (address + size > n.avl[@intFromEnum(AVL_type.Address)].value +
                n.avl[@intFromEnum(AVL_type.Size)].value)
                return Error.NoSpaceFound;
            if (n.avl[@intFromEnum(AVL_type.Address)].value == address and
                n.avl[@intFromEnum(AVL_type.Size)].value == size)
            {
                self.used_space += size;
                self.remove_from_tree(n, AVL_type.Size);
                self.remove_from_tree(n, AVL_type.Address);
                free_node(n);
                return;
            } else if (n.avl[@intFromEnum(AVL_type.Address)].value +
                n.avl[@intFromEnum(AVL_type.Size)].value == address + size)
            {
                self.used_space += size;
                self.remove_from_tree(n, AVL_type.Size);
                n.avl[@intFromEnum(AVL_type.Size)].value -= size;
                self.add_to_tree(n, AVL_type.Size);
                return;
            } else if (n.avl[@intFromEnum(AVL_type.Address)].value == address) {
                self.used_space += size;
                self.remove_from_tree(n, AVL_type.Size);
                n.avl[@intFromEnum(AVL_type.Size)].value -= size;
                self.add_to_tree(n, AVL_type.Size);
                n.avl[@intFromEnum(AVL_type.Address)].value += size;
            } else {
                const tmp = n.avl[@intFromEnum(AVL_type.Address)].value + n.avl[@intFromEnum(AVL_type.Size)].value;
                try self.set_used(
                    address,
                    (n.avl[@intFromEnum(AVL_type.Address)].value + n.avl[@intFromEnum(AVL_type.Size)].value) -
                        (address),
                );
                return self.free_space(address + size, tmp - (address + size));
            }
        } else return Error.NoSpaceFound;
    }

    pub fn add_space(self: *Self, address: usize, size: usize) !void {
        self.used_space += size;
        try self.free_space(address, size);
    }

    /// free the space of size size at address
    pub fn free_space(self: *Self, address: usize, size: usize) !void {
        var current_node: ?*Node = self.tree[@intFromEnum(AVL_type.Address)];
        var left: ?*Node = null;
        var right: ?*Node = null;

        // first check if there is other nodes to merge with this one
        while (current_node) |n| {
            if (n.avl[@intFromEnum(AVL_type.Address)].value >= address + size) {
                if (n.avl[@intFromEnum(AVL_type.Address)].value == address + size) {
                    // we found a node to merge on the right
                    right = n;
                }
                current_node = n.avl[@intFromEnum(AVL_type.Address)].l;
            } else if (n.avl[@intFromEnum(AVL_type.Address)].value + n.avl[@intFromEnum(AVL_type.Size)].value <=
                address)
            {
                if (n.avl[@intFromEnum(AVL_type.Address)].value + n.avl[@intFromEnum(AVL_type.Size)].value ==
                    address)
                {
                    // we found a node to merge on the left
                    left = n;
                }
                current_node = n.avl[@intFromEnum(AVL_type.Address)].r;
            } else return Error.DoubleFree;
        }

        if (left) |l| {
            self.remove_from_tree(l, AVL_type.Size);
            l.avl[@intFromEnum(AVL_type.Size)].value += size;
            if (right) |r| {
                self.remove_from_tree(r, AVL_type.Address);
                self.remove_from_tree(r, AVL_type.Size);
                l.avl[@intFromEnum(AVL_type.Size)].value += r.avl[@intFromEnum(AVL_type.Size)].value;
                free_node(r);
            }
            self.add_to_tree(l, AVL_type.Size);
        } else {
            if (right) |r| {
                self.remove_from_tree(r, AVL_type.Address);
                self.remove_from_tree(r, AVL_type.Size);
                r.avl[@intFromEnum(AVL_type.Address)].value -= size;
                r.avl[@intFromEnum(AVL_type.Size)].value += size;
                self.add_to_tree(r, AVL_type.Address);
                self.add_to_tree(r, AVL_type.Size);
            } else {
                var node = try alloc_node();
                node.avl[@intFromEnum(AVL_type.Address)].value = address;
                node.avl[@intFromEnum(AVL_type.Size)].value = size;
                self.add_to_tree(node, AVL_type.Address);
                self.add_to_tree(node, AVL_type.Size);
            }
        }
        self.used_space -= size;
    }

    /// AVL tree rotation, rotate the node `n` in the tree `field` in the direction `dir` ("l" or "r")
    fn rotate(self: *Self, n: *Node, field: AVL_type, comptime dir: []const u8) void {
        const other_dir = comptime if (ft.mem.eql(u8, dir, "l")) "r" else "l";
        const ref = self.node_ref(n, field);

        const l: *Node = @field(n.avl[@intFromEnum(field)], dir) orelse return;
        const op: ?*Node = n.avl[@intFromEnum(field)].p;

        const bn = n.avl[@intFromEnum(field)].balance_factor;
        const bl = l.avl[@intFromEnum(field)].balance_factor;
        if (comptime ft.mem.eql(u8, dir, "l")) {
            if (bl > 0) {
                n.avl[@intFromEnum(field)].balance_factor -= 1 + bl;
                l.avl[@intFromEnum(field)].balance_factor = -1 + @min(bl, bn - 1);
            } else {
                n.avl[@intFromEnum(field)].balance_factor -= 1;
                l.avl[@intFromEnum(field)].balance_factor = bl - 1 + @min(0, bn - 1);
            }
        } else {
            if (bl < 0) {
                n.avl[@intFromEnum(field)].balance_factor += 1 - bl;
                l.avl[@intFromEnum(field)].balance_factor = 1 + @max(bn + 1, bl);
            } else {
                n.avl[@intFromEnum(field)].balance_factor += 1;
                l.avl[@intFromEnum(field)].balance_factor = bl + 1 + @max(bn + 1, 0);
            }
        }

        @field(n.avl[@intFromEnum(field)], dir) = @field(l.avl[@intFromEnum(field)], other_dir);
        if (@field(n.avl[@intFromEnum(field)], dir)) |nl|
            nl.avl[@intFromEnum(field)].p = n;

        @field(l.avl[@intFromEnum(field)], other_dir) = n;
        if (@field(l.avl[@intFromEnum(field)], other_dir)) |lr|
            lr.avl[@intFromEnum(field)].p = l;

        ref.* = l;
        l.avl[@intFromEnum(field)].p = op;
    }

    /// debug function, used to check that a tree respect the rules of the AVL algorithm,
    /// this function panic if the tree is invalid
    fn check_node(self: *Self, n: *Node, field: AVL_type) i32 {
        const dl: i32 = if (n.avl[@intFromEnum(field)].l) |l| self.check_node(l, field) else 0;
        const dr: i32 = if (n.avl[@intFromEnum(field)].r) |r| self.check_node(r, field) else 0;
        if (dl - dr != n.avl[@intFromEnum(field)].balance_factor or
            n.avl[@intFromEnum(field)].balance_factor > 1 or
            n.avl[@intFromEnum(field)].balance_factor < -1)
        {
            self.print();
            @panic("invalid tree in " ++ @typeName(Self));
        }
        return @max(dl, dr) + 1;
    }

    /// fix the node `n` in the tree `field`, the parameter `change` indicate the weight modification of the node,
    /// eg: 1 if the node is 1 node heavier than before or -1 if the node is 1 node lighter than before
    fn fix(self: *Self, n: *Node, field: AVL_type, change: i8) void {
        if (n.avl[@intFromEnum(field)].p) |p| {
            if (p.avl[@intFromEnum(field)].l) |pl| if (pl == n) {
                p.avl[@intFromEnum(field)].balance_factor += change;
            };
            if (p.avl[@intFromEnum(field)].r) |pr| if (pr == n) {
                p.avl[@intFromEnum(field)].balance_factor -= change;
            };

            if (p.avl[@intFromEnum(field)].balance_factor == 0) {
                if (change == -1) {
                    return self.fix(p, field, change);
                }
                return;
            } else if (p.avl[@intFromEnum(field)].balance_factor == 1 or
                p.avl[@intFromEnum(field)].balance_factor == -1)
            {
                if (change == 1) {
                    return self.fix(p, field, change);
                }
                return;
            } else if (p.avl[@intFromEnum(field)].balance_factor == 2) {
                if (p.avl[@intFromEnum(field)].l) |l| if (l.avl[@intFromEnum(field)].balance_factor < 0) {
                    self.rotate(l, field, "r");
                };
                self.rotate(p, field, "l");
            } else if (p.avl[@intFromEnum(field)].balance_factor == -2) {
                if (p.avl[@intFromEnum(field)].r) |r| if (r.avl[@intFromEnum(field)].balance_factor > 0) {
                    self.rotate(r, field, "l");
                };
                self.rotate(p, field, "r");
            } else unreachable;

            if (p.avl[@intFromEnum(field)].p) |new_p| {
                if (new_p.avl[@intFromEnum(field)].balance_factor == 0) {
                    if (change == -1) {
                        return self.fix(new_p, field, change);
                    }
                    return;
                }
            }
        }
    }

    /// add the node `n` to the tree `field`
    fn add_to_tree(self: *Self, n: *Node, field: AVL_type) void {
        n.avl[@intFromEnum(field)].l = null;
        n.avl[@intFromEnum(field)].r = null;
        n.avl[@intFromEnum(field)].p = null;
        n.avl[@intFromEnum(field)].balance_factor = 0;

        if (self.tree[@intFromEnum(field)]) |root| {
            var current_node: *Node = root;

            while (true) {
                if (current_node.avl[@intFromEnum(field)].value > n.avl[@intFromEnum(field)].value) {
                    if (current_node.avl[@intFromEnum(field)].l) |l| {
                        current_node = l;
                    } else {
                        current_node.avl[@intFromEnum(field)].l = n;
                        n.avl[@intFromEnum(field)].p = current_node;
                        break;
                    }
                } else {
                    if (current_node.avl[@intFromEnum(field)].r) |r| {
                        current_node = r;
                    } else {
                        current_node.avl[@intFromEnum(field)].r = n;
                        n.avl[@intFromEnum(field)].p = current_node;
                        break;
                    }
                }
            }
        } else {
            self.tree[@intFromEnum(field)] = n;
            n.avl[@intFromEnum(field)].p = null;
        }
        self.fix(n, field, 1);
        if (@import("build_options").optimize == .Debug) {
            _ = if (self.tree[@intFromEnum(field)]) |r| self.check_node(r, field);
        }
    }

    /// remove the node `n` from the tree `field`
    fn remove_from_tree(self: *Self, n: *Node, field: AVL_type) void {
        const ref: *?*Node = self.node_ref(n, field);

        if (n.avl[@intFromEnum(field)].l) |l| {
            if (n.avl[@intFromEnum(field)].r) |_| {
                if (next_node(n, field)) |next| {
                    self.swap_nodes(n, next, field);
                    return self.remove_from_tree(n, field);
                } else unreachable;
            } else {
                self.fix(n, field, -1);
                ref.* = l;
                l.avl[@intFromEnum(field)].p = n.avl[@intFromEnum(field)].p;
            }
        } else if (n.avl[@intFromEnum(field)].r) |r| {
            self.fix(n, field, -1);
            ref.* = r;
            r.avl[@intFromEnum(field)].p = n.avl[@intFromEnum(field)].p;
        } else {
            self.fix(n, field, -1);
            ref.* = null;
        }

        if (@import("build_options").optimize == .Debug) {
            _ = if (self.tree[@intFromEnum(field)]) |r| self.check_node(r, field);
        }
    }

    /// return the "reference" of a node (a pointer to the pointer to this node)
    fn node_ref(self: *Self, n: *Node, field: AVL_type) *?*Node {
        if (n.avl[@intFromEnum(field)].p) |p| {
            if (p.avl[@intFromEnum(field)].l) |*pl| {
                if (pl.* == n) {
                    return &p.avl[@intFromEnum(field)].l;
                }
            }
            if (p.avl[@intFromEnum(field)].r) |*pr| {
                if (pr.* == n) {
                    return &p.avl[@intFromEnum(field)].r;
                }
            }
            @panic("invalid tree");
        } else {
            return &self.tree[@intFromEnum(field)];
        }
    }

    /// swap the nodes `a` and `b` in the tree `field`
    fn swap_nodes(self: *Self, a: *Node, b: *Node, field: AVL_type) void {
        const a_ref = self.node_ref(a, field);
        const b_ref = self.node_ref(b, field);

        ft.mem.swap(?*Node, a_ref, b_ref);
        ft.mem.swap(i8, &a.avl[@intFromEnum(field)].balance_factor, &b.avl[@intFromEnum(field)].balance_factor);
        ft.mem.swap(?*Node, &a.avl[@intFromEnum(field)].p, &b.avl[@intFromEnum(field)].p);
        ft.mem.swap(?*Node, &a.avl[@intFromEnum(field)].l, &b.avl[@intFromEnum(field)].l);
        if (a.avl[@intFromEnum(field)].l) |l| {
            l.avl[@intFromEnum(field)].p = a;
        }
        if (b.avl[@intFromEnum(field)].l) |l| {
            l.avl[@intFromEnum(field)].p = b;
        }
        ft.mem.swap(?*Node, &a.avl[@intFromEnum(field)].r, &b.avl[@intFromEnum(field)].r);
        if (a.avl[@intFromEnum(field)].r) |r| {
            r.avl[@intFromEnum(field)].p = a;
        }
        if (b.avl[@intFromEnum(field)].r) |r| {
            r.avl[@intFromEnum(field)].p = b;
        }
    }

    /// return the next node in the tree
    fn next_node(n: *Node, field: AVL_type) ?*Node {
        if (n.avl[@intFromEnum(field)].r) |r| {
            var ret = r;
            while (ret.avl[@intFromEnum(field)].l) |l| {
                ret = l;
            } else {
                return ret;
            }
        } else {
            var current: ?*Node = n;
            while (current) |c| {
                if (c.avl[@intFromEnum(field)].p) |p| {
                    if (c == p.avl[@intFromEnum(field)].r) {
                        current = p;
                    } else break;
                } else break;
            }
            if (current) |c| {
                return c.avl[@intFromEnum(field)].p;
            }
            return null;
        }
    }

    /// alloc one node
    fn alloc_node() !*Node {
        const ret = Node.cache.allocator().create(Node) catch {
            @panic("cannot allocate node for virtual_space_allocator");
        };
        ret.* = .{};
        return ret;
    }

    /// free one node
    fn free_node(n: *Node) void {
        n.* = .{};
        Node.cache.allocator().free(@as([*]Node, @ptrCast(n))[0..1]);
    }

    /// print recursively the content of a node in the tree `field`, `depth` is the depth of this node
    fn print_node(self: *Self, n: *Node, field: AVL_type, depth: u32) void {
        const printk = @import("../tty/tty.zig").printk;
        if (n.avl[@intFromEnum(field)].l) |l| {
            self.print_node(l, field, depth + 1);
        }
        for (0..depth) |_| {
            printk(" ", .{});
        }
        printk("0x{x} (n: 0x{x:0>8} p: 0x{x:0>8}) balance_factor: {d}\n", .{
            n.avl[@intFromEnum(field)].value,
            @as(u32, @intFromPtr(n)),
            @as(u32, @intFromPtr(n.avl[@intFromEnum(field)].p)),
            n.avl[@intFromEnum(field)].balance_factor,
        });
        if (n.avl[@intFromEnum(field)].r) |r| {
            self.print_node(r, field, depth + 1);
        }
    }

    /// print the two AVLs using printk
    pub fn print(self: *Self) void {
        const printk = @import("../tty/tty.zig").printk;
        printk("\naddress tree:\n", .{});
        if (self.tree[@intFromEnum(AVL_type.Address)]) |r| {
            self.print_node(r, AVL_type.Address, 0);
        }
        printk("\nsize tree:\n", .{});
        if (self.tree[@intFromEnum(AVL_type.Size)]) |r| {
            self.print_node(r, AVL_type.Size, 0);
        }
        printk("\n", .{});
    }
};
