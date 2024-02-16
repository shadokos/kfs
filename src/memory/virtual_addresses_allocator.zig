const ft = @import("../ft/ft.zig");
const paging = @import("paging.zig");

pub fn VirtualAddressesAllocator(comptime PageAllocator : type) type {
	return struct {

		pageAllocator : *PageAllocator = undefined,

		tree : [2]?*Node = .{null, null},

		free_nodes : ?*Node = null,

		node_pages : ?*NodePage = null,

		boostrap_page : NodePage align(paging.page_size) = .{},

		used_space : usize = 0,

		const AVL_type = enum(u1) {
			Size,
			Address
		};

		const Node = extern struct {
			avl : [2]AVL_hdr = .{.{}, .{}},
			next : ?*@This() = null,

			const AVL_hdr = extern struct {
				l : ?*Node = null,
				r : ?*Node = null,
				p : ?*Node = null,
				value : usize = undefined,
			};
		};

		const NodePage = extern struct {
			hdr : Header = .{},
			nodes : [nodes_per_pages]Node = undefined,

			const Header = extern struct {
				next : ?*NodePage = null,
				first_node : usize = 0,
				free_nodes_count : usize = (paging.page_size - @sizeOf(@This())) / @sizeOf(Node),
			};

			const nodes_per_pages = (paging.page_size - @sizeOf(Header)) / @sizeOf(Node);
		};

		const Self = @This();

		pub const Error = error{NoSpaceFound};

		pub fn init(self : *Self, _pageAllocator : *PageAllocator, address : usize, size : usize) !void {
			self.pageAllocator = _pageAllocator;

				var node = try self.alloc_node();
			node.avl[@intFromEnum(AVL_type.Address)].value = address;
			node.avl[@intFromEnum(AVL_type.Size)].value = size;
			self.tree[@intFromEnum(AVL_type.Address)] = node;
			self.tree[@intFromEnum(AVL_type.Size)] = node;
		}

		pub fn alloc_space(self : *Self, size : usize) Error!usize {
			var current_node : ?*Node = self.tree[@intFromEnum(AVL_type.Size)];
			var best_fit : ?*Node = null;

			while (current_node) |n| {
				if (n.avl[@intFromEnum(AVL_type.Size)].value > size) {
					best_fit = n;
					current_node = n.avl[@intFromEnum(AVL_type.Size)].l;
				} else if (n.avl[@intFromEnum(AVL_type.Size)].value < size) {
					current_node = n.avl[@intFromEnum(AVL_type.Size)].r;
				} else {
					// @import("../tty/tty.zig").printk("bonjou\rn",.{});
					best_fit = n;
					break;
				}
			}
			if (best_fit) |n| {
				self.used_space += size;
				// @import("../tty/tty.zig").printk("size: {d} {d}\n",.{n.avl[@intFromEnum(AVL_type.Size)].value, size});
				if (n.avl[@intFromEnum(AVL_type.Size)].value == size) {
					const ret = n.avl[@intFromEnum(AVL_type.Address)].value;
					self.remove_from_tree(n, AVL_type.Size);
					// self.print();
					self.remove_from_tree(n, AVL_type.Address);
					self.free_node(n);
					// @import("../tty/tty.zig").printk("coucou\n",.{});

					// self.print();
					return ret;
				} else {
					const ret = n.avl[@intFromEnum(AVL_type.Address)].value + n.avl[@intFromEnum(AVL_type.Size)].value - size;
					self.remove_from_tree(n, AVL_type.Size);
					n.avl[@intFromEnum(AVL_type.Size)].value -= size;
					self.add_to_tree(n, AVL_type.Size);
					return ret;
				}
			} else return Error.NoSpaceFound;
		}

		pub fn set_used(self : *Self, address : usize, size : usize) (Error || PageAllocator.Error)!void {
			var current_node : ?*Node = self.tree[@intFromEnum(AVL_type.Address)];
			// @import("../tty/tty.zig").printk("whouhwho {d} {d}\n", .{address, size});

			while (current_node) |n| {
				if (n.avl[@intFromEnum(AVL_type.Address)].value > address) {
					current_node = n.avl[@intFromEnum(AVL_type.Address)].l;
				} else if (n.avl[@intFromEnum(AVL_type.Address)].value + n.avl[@intFromEnum(AVL_type.Size)].value < address) {
					// @import("../tty/tty.zig").printk("asdfqwerty \n", .{});
					current_node = n.avl[@intFromEnum(AVL_type.Address)].r;
				} else break;
			}
			if (current_node) |n| {
				// @import("../tty/tty.zig").printk("whouhwho {d} {d}\n", .{address, size});
				// @import("../tty/tty.zig").printk("coucou2 {d} {d}\n", .{n.avl[@intFromEnum(AVL_type.Address)].value, n.avl[@intFromEnum(AVL_type.Size)].value});
				if (address + size > n.avl[@intFromEnum(AVL_type.Address)].value + n.avl[@intFromEnum(AVL_type.Size)].value)
					return Error.NoSpaceFound;
				if (n.avl[@intFromEnum(AVL_type.Address)].value == address and n.avl[@intFromEnum(AVL_type.Size)].value == size) {
					self.used_space += size;
					self.remove_from_tree(n, AVL_type.Size);
					self.remove_from_tree(n, AVL_type.Address);
					self.free_node(n);
					return ;
				} else if (n.avl[@intFromEnum(AVL_type.Address)].value + n.avl[@intFromEnum(AVL_type.Size)].value == address + size) {
					self.used_space += size;
					self.remove_from_tree(n, AVL_type.Size);
					n.avl[@intFromEnum(AVL_type.Size)].value -= size;
					self.add_to_tree(n, AVL_type.Size);
					return ;
				} else if (n.avl[@intFromEnum(AVL_type.Address)].value == address) {
					self.used_space += size;
					self.remove_from_tree(n, AVL_type.Size);
					n.avl[@intFromEnum(AVL_type.Size)].value -= size;
					self.add_to_tree(n, AVL_type.Size);
					n.avl[@intFromEnum(AVL_type.Address)].value += size;
				} else {
					const tmp =	n.avl[@intFromEnum(AVL_type.Address)].value + n.avl[@intFromEnum(AVL_type.Size)].value;
					try self.set_used(address, (n.avl[@intFromEnum(AVL_type.Address)].value + n.avl[@intFromEnum(AVL_type.Size)].value) - (address));
					return self.free_space(address + size, tmp - (address + size));
				}
			} else return Error.NoSpaceFound;

		}

		pub fn free_space(self : *Self, address : usize, size : usize) (Error || PageAllocator.Error)!void {
			var current_node : ?*Node = self.tree[@intFromEnum(AVL_type.Size)];
			var left : ?*Node = null;
			var right : ?*Node = null;
			// self.print();

			// first check if there is other nodes to merge with this one
			while (current_node) |n| {
				if (n.avl[@intFromEnum(AVL_type.Address)].value >= address + size) {
					if (n.avl[@intFromEnum(AVL_type.Address)].value + n.avl[@intFromEnum(AVL_type.Size)].value == address) {
						// we found a node to merge on the left
						left = n;
					}
					current_node = n.avl[@intFromEnum(AVL_type.Address)].l;
				} else if (n.avl[@intFromEnum(AVL_type.Address)].value + n.avl[@intFromEnum(AVL_type.Size)].value <= address) {
					if (n.avl[@intFromEnum(AVL_type.Address)].value == address + size) {
						// we found a node to merge on the right
						right = n;
					}
					current_node = n.avl[@intFromEnum(AVL_type.Address)].r;
				} else @panic("free_space");
			}

			if (left) |l| {
				self.remove_from_tree(l, AVL_type.Size);
				l.avl[@intFromEnum(AVL_type.Size)].value += size;
				if (right) |r| {
					self.remove_from_tree(r, AVL_type.Address);
					self.remove_from_tree(r, AVL_type.Size);
					l.avl[@intFromEnum(AVL_type.Size)].value += r.avl[@intFromEnum(AVL_type.Size)].value;
					self.free_node(r);
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
					var node = try self.alloc_node();
					node.avl[@intFromEnum(AVL_type.Address)].value = address;
					node.avl[@intFromEnum(AVL_type.Size)].value = size;
					self.add_to_tree(node, AVL_type.Address);
					self.add_to_tree(node, AVL_type.Size);
				}
			}
			self.used_space -= size;
			// self.print();
		}

		fn add_to_tree(self : *Self, n : *Node, field : AVL_type) void {
			n.avl[@intFromEnum(field)].l = null;
			n.avl[@intFromEnum(field)].r = null;

			if (self.tree[@intFromEnum(field)]) |root| {
				var current_node : *Node = root;

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
		}

		fn remove_from_tree(self : *Self, n : *Node, field : AVL_type) void {

			var ref : *?*Node = self.node_ref(n, field);
			// @import("../tty/tty.zig").printk("n: 0x{x} p: 0x{x} ref 0x{x}\n",.{@intFromPtr(n), @intFromPtr(n.avl[@intFromEnum(field)].p), @intFromPtr(ref)});
			n.avl[@intFromEnum(field)].p = null;

			if (n.avl[@intFromEnum(field)].l) |l| {
				if (n.avl[@intFromEnum(field)].r) |_| {
					if (next_node(n, field)) |next| {
						self.swap_nodes(n, next, field);
						return self.remove_from_tree(n, field);
					} else unreachable;
				}
				else {
					ref.* = l;
					l.avl[@intFromEnum(field)].p = n.avl[@intFromEnum(field)].p;
				}
			} else if (n.avl[@intFromEnum(field)].r) |r| {
				ref.* = r;
				r.avl[@intFromEnum(field)].p = n.avl[@intFromEnum(field)].p;
			} else ref.* = null;
		}

		fn node_ref(self : *Self, n : *Node, field : AVL_type) *?*Node {
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
			}
			else {
				return &self.tree[@intFromEnum(field)];
			}
		}

		fn swap_nodes(self : *Self, a : *Node, b : *Node, field : AVL_type) void {
			const a_ref = self.node_ref(a, field);
			const b_ref = self.node_ref(b, field);

			ft.mem.swap(?*Node, a_ref, b_ref);
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
			ft.mem.swap(?*Node, &a.avl[@intFromEnum(field)].p, &b.avl[@intFromEnum(field)].p);
		}

		fn next_node(n : *Node, field : AVL_type) ?*Node { // todo
			if (n.avl[@intFromEnum(field)].r) |r| {
				var ret = r;
				while (ret.avl[@intFromEnum(field)].l) |l| {
					ret = l;
				} else {
					return ret;
				}
			}
			else return null;
		}

		fn page_of_node(n : *Node) *NodePage {
			return @ptrFromInt(ft.mem.alignBackward(usize, @intFromPtr(n), paging.page_size));
		}

		fn alloc_node(self : *Self) (PageAllocator.Error || Error)!*Node {
			if (self.free_nodes) |n| {
				self.free_nodes = n.next;
				// @import("../tty/tty.zig").printk("new node {x}\n", .{@intFromPtr(n)});
				return n;
			}

			if (self.node_pages) |p| {
				if (p.hdr.first_node != NodePage.nodes_per_pages) {
					const ret = &p.nodes[p.hdr.first_node];
					p.hdr.first_node += 1;
					p.hdr.free_nodes_count -= 1;
					// @import("../tty/tty.zig").printk("new node {x}\n", .{@intFromPtr(ret)});
					return ret;
				}
			}

			const new_page : *NodePage = @ptrCast(@alignCast(try self.pageAllocator.alloc_pages(1)));

			new_page.* = .{};
			new_page.hdr.next = self.node_pages;
			self.node_pages = new_page;
			return self.alloc_node();
		}

		fn free_node(self : *Self, n : *Node) void {
			const page = page_of_node(n);
			page.hdr.free_nodes_count += 1;  // here we can free empty pages if we want
			n.next = self.free_nodes;
			self.free_nodes = n;
		}

		fn print_node(self : *Self, n : *Node, field : AVL_type, depth : u32) void {
			const printk = @import("../tty/tty.zig").printk;
			if (n.avl[@intFromEnum(field)].l) |l| {
				self.print_node(l, field, depth + 1);
			}
			for (0..depth) |_| {
				printk(" ", .{});
			}
			printk("0x{x} (n: 0x{x:0>8} p: 0x{x:0>8})\n", .{n.avl[@intFromEnum(field)].value, @as(u32, @intFromPtr(n)), @as(u32, @intFromPtr(n.avl[@intFromEnum(field)].p))});
			if (n.avl[@intFromEnum(field)].r) |r| {
				self.print_node(r, field, depth + 1);
			}
		}

		pub fn print(self : *Self) void {
			const printk = @import("../tty/tty.zig").printk;
			if (self.tree[@intFromEnum(AVL_type.Address)]) |r| {
				printk("\naddress tree:\n", .{});
				self.print_node(r, AVL_type.Address, 0);
			}
			if (self.tree[@intFromEnum(AVL_type.Size)]) |r| {
				printk("\nsize tree:\n", .{});
				self.print_node(r, AVL_type.Size, 0);
			}
		}
	};
}
