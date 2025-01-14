const ft = @import("ft.zig");

pub fn TailQueue(comptime T: type) type {
    return struct {
        first: ?*Node = null,
        last: ?*Node = null,
        len: usize = 0,

        pub const Node = struct {
            prev: ?*Node = null,
            next: ?*Node = null,
            data: T,
        };

        const Self = @This();

        pub fn append(list: *Self, new_node: *Node) void {
            if (list.last) |l| {
                new_node.prev = l;
                new_node.next = null;
                l.next = new_node;
                list.last = new_node;
            } else {
                list.first = new_node;
                list.last = new_node;
                new_node.next = null;
                new_node.prev = null;
            }
            list.len += 1;
        }

        pub fn concatByMoving(list1: *Self, list2: *Self) void {
            if (list1.last) |l1| {
                l1.next = list2.first;
                if (list2.first) |f2| {
                    f2.prev = l1;
                }
                list1.last = list2.last;
            } else {
                list1 = list2;
            }
            list1.len += list2.len;
            list2 = .{};
        }

        pub fn insertAfter(list: *Self, node: *Node, new_node: *Node) void {
            new_node.prev = node;
            node.next = new_node;
            if (node.next) |next| {
                new_node.next = next;
                next.prev = new_node;
            } else {
                new_node.next = null;
                list.last = new_node;
            }
            list.len += 1;
        }

        pub fn insertBefore(list: *Self, node: *Node, new_node: *Node) void {
            new_node.next = node;
            node.prev = new_node;
            if (node.prev) |prev| {
                new_node.prev = prev;
                prev.next = new_node;
            } else {
                new_node.prev = null;
                list.first = new_node;
            }
            list.len += 1;
        }

        pub fn pop(list: *Self) ?*Node {
            if (list.last) |l| {
                list.remove(l);
                return l;
            } else {
                return null;
            }
        }

        pub fn popFirst(list: *Self) ?*Node {
            if (list.first) |f| {
                list.remove(f);
                return f;
            } else {
                return null;
            }
        }

        pub fn prepend(list: *Self, new_node: *Node) void {
            if (list.first) |f| {
                new_node.prev = null;
                new_node.next = f;
                f.prev = new_node;
                list.first = new_node;
            } else {
                list.first = new_node;
                list.last = new_node;
                new_node.next = null;
                new_node.prev = null;
            }
            list.len += 1;
        }
        pub fn remove(list: *Self, node: *Node) void {
            if (node.prev) |p| {
                p.next = node.next;
            } else {
                list.first = node.next;
            }
            if (node.next) |n| {
                n.prev = node.prev;
            } else {
                list.last = node.prev;
            }
            list.len -= 1;
        }
    };
}
