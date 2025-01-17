pub fn DoublyLinkedList(comptime T: type) type {
    return struct {
        const Self = @This();

        pub const Node = struct {
            prev: ?*Node = null,
            next: ?*Node = null,
            data: T,
        };

        first: ?*Node = null,
        last: ?*Node = null,
        len: usize = 0,

        // Insert a new node at the end of the list.
        pub fn append(list: *Self, new_node: *Node) void {
            if (list.last) |n| {
                list.insertAfter(n, new_node);
                return;
            }
            new_node.prev = null;
            new_node.next = null;
            list.first = new_node;
            list.last = new_node;
            list.len = 1;
        }

        // Concatenate list2 onto the end of list1, removing all entries from the former.
        pub fn concatByMoving(list1: *Self, list2: *Self) void {
            const list2_head = if (list2.first) |n| n else return;
            if (list1.last) |n| {
                n.next = list2_head;
                list2_head.prev = n;
            } else {
                list1.first = list2_head;
            }
            list1.last = list2.last;
            list1.len += list2.len;
            list2.first = null;
            list2.last = null;
            list2.len = 0;
        }

        // Insert a new node after an existing one.
        pub fn insertAfter(list: *Self, node: *Node, new_node: *Node) void {
            new_node.prev = node;
            new_node.next = node.next;
            if (node.next) |n| n.prev = new_node else list.last = new_node;
            node.next = new_node;
            list.len += 1;
        }

        // Insert a new node before an existing one.
        pub fn insertBefore(list: *Self, node: *Node, new_node: *Node) void {
            new_node.prev = node.prev;
            new_node.next = node;
            if (node.prev) |n| n.next = new_node else list.first = new_node;
            node.prev = new_node;
            list.len += 1;
        }

        // Remove and return the last node in the list.
        pub fn pop(list: *Self) ?*Node {
            if (list.last) |n| {
                list.remove(n);
                return n;
            }
            return null;
        }

        // Remove and return the first node in the list.
        pub fn popFirst(list: *Self) ?*Node {
            if (list.first) |n| {
                list.remove(n);
                return n;
            }
            return null;
        }

        // Insert a new node at the beginning of the list.
        pub fn prepend(list: *Self, new_node: *Node) void {
            if (list.first) |n| {
                list.insertBefore(n, new_node);
                return;
            }
            new_node.prev = null;
            new_node.next = null;
            list.first = new_node;
            list.last = new_node;
            list.len = 1;
        }

        // Remove a node from the list.
        pub fn remove(list: *Self, node: *Node) void {
            if (node.prev) |n| n.next = node.next else list.first = node.next;
            if (node.next) |n| n.prev = node.prev else list.last = node.prev;
            list.len -= 1;
        }
    };
}

// SinglyLinkedList implementation following the Zig standard library interface.
pub fn SinglyLinkedList(comptime T: type) type {
    return struct {
        // Type definitions ---------------------------------------------------------------------------------------- //

        const Self = @This();

        pub const Node = struct {
            pub const Data = T;

            data: T,
            next: ?*Node = null,

            // Iterate over each next node, returning the count of all nodes except the starting one.
            // This operation is O(N).
            pub fn countChildren(node: *const Node) usize {
                var ret: usize = 0;
                var next = node.next;
                while (next) |n| : (next = n.next) ret += 1;
                return ret;
            }

            // Iterate over the singly-linked list from this node, until the final node is found.
            // This operation is O(N).
            pub fn findLast(node: *Node) *Node {
                var current: ?*Node = node;
                var last: *Node = node;
                while (current) |n| : (current = n.next) last = n;
                return last;
            }

            // Insert a new node after the current one.
            pub fn insertAfter(node: *Node, new_node: *Node) void {
                new_node.next = node.next;
                node.next = new_node;
            }

            // Remove a node from the list.
            pub fn removeNext(node: *Node) ?*Node {
                const next = node.next;
                if (next) |n| {
                    node.next = n.next;
                    return n;
                }
                return null;
            }

            // Reverse the list starting from this node in-place. This operation is O(N).
            pub fn reverse(indirect: *?*Node) void {
                if (indirect.* == null) return;
                var prev: ?*Node = null;
                var current = indirect.*;
                while (current) |n| {
                    const next = n.next;
                    n.next = prev;
                    prev = n;
                    current = next;
                }
                indirect.* = prev;
            }
        };

        // Fields -------------------------------------------------------------------------------------------------- //

        first: ?*Node = null,

        // Methods ------------------------------------------------------------------------------------------------- //

        // Iterate over all nodes, returning the count. This operation is O(N).
        pub fn len(list: Self) usize {
            return if (list.first) |n| Node.countChildren(n) + 1 else 0;
        }

        // Remove and return the first node in the list.
        pub fn popFirst(list: *Self) ?*Node {
            const first = list.first;
            if (first) |n| {
                list.first = n.next;
                return n;
            }
            return null;
        }

        // Insert a new node at the head.
        pub fn prepend(list: *Self, new_node: *Node) void {
            new_node.next = list.first;
            list.first = new_node;
        }

        // Remove a node from the list.
        pub fn remove(list: *Self, node: *Node) void {
            if (list.first == node) list.first = node.next;

            var current = list.first;
            while (current) |n| : (current = n.next) {
                if (n.next == node) {
                    n.next = node.next;
                    break;
                }
            }
        }
    };
}

test "FT TEST: SinglyLinkedList test" {
    const std = @import("std");
    const testing = std.testing;

    const L = SinglyLinkedList(u32);

    var list = L{};

    // Test empty list
    try testing.expect(list.len() == 0);
    try testing.expect(list.first == null);

    // Test prepend and len
    var node1 = L.Node{ .data = 10 };
    list.prepend(&node1);
    try testing.expect(list.len() == 1);
    try testing.expect(list.first == &node1);

    var node2 = L.Node{ .data = 20 };
    list.prepend(&node2);
    try testing.expect(list.len() == 2);
    try testing.expect(list.first == &node2);

    // Test insertAfter
    var node3 = L.Node{ .data = 30 };
    node2.insertAfter(&node3);
    try testing.expect(list.len() == 3);
    try testing.expect(node2.next == &node3);

    // Test removeNext
    const removed_node = node2.removeNext();
    try testing.expect(removed_node == &node3);
    try testing.expect(list.len() == 2);
    try testing.expect(node2.next == &node1);

    // Test popFirst
    const popped_node = list.popFirst();
    try testing.expect(popped_node == &node2);
    try testing.expect(list.len() == 1);
    try testing.expect(list.first == &node1);

    // Test remove
    list.remove(&node1);
    try testing.expect(list.len() == 0);
    try testing.expect(list.first == null);

    // Test reverse
    list.prepend(&node1);
    list.prepend(&node2);
    list.prepend(&node3);
    L.Node.reverse(&list.first);
    try testing.expect(list.first == &node1);
    try testing.expect(list.first.?.next == &node2);
    try testing.expect(list.first.?.next.?.next == &node3);
    try testing.expect(list.first.?.next.?.next.?.next == null);

    // Test findLast
    const last_node = L.Node.findLast(&node1);
    try testing.expect(last_node == &node3);

    // Test countChildren
    const count = L.Node.countChildren(&node1);
    try testing.expect(count == 2);
}

test "FT TEST: DoublyLinkedList tests" {
    const std = @import("std");
    const testing = std.testing;

    const L = DoublyLinkedList(u32);

    var list = L{};

    // Test empty list
    try testing.expect(list.len == 0);
    try testing.expect(list.first == null);
    try testing.expect(list.last == null);

    // Test append and len
    var node1 = L.Node{ .data = 10 };
    list.append(&node1);
    try testing.expect(list.len == 1);
    try testing.expect(list.first == &node1);
    try testing.expect(list.last == &node1);

    var node2 = L.Node{ .data = 20 };
    list.append(&node2);
    try testing.expect(list.len == 2);
    try testing.expect(list.first == &node1);
    try testing.expect(list.last == &node2);

    // Test prepend
    var node3 = L.Node{ .data = 30 };
    list.prepend(&node3);
    try testing.expect(list.len == 3);
    try testing.expect(list.first == &node3);
    try testing.expect(list.last == &node2);

    // Test insertAfter
    var node4 = L.Node{ .data = 40 };
    list.insertAfter(&node1, &node4);
    try testing.expect(list.len == 4);
    try testing.expect(node1.next == &node4);
    try testing.expect(node4.prev == &node1);

    // Test insertBefore
    var node5 = L.Node{ .data = 50 };
    list.insertBefore(&node2, &node5);
    try testing.expect(list.len == 5);
    try testing.expect(node5.next == &node2);
    try testing.expect(node2.prev == &node5);

    // Test pop
    const popped_node = list.pop();
    try testing.expect(popped_node == &node2);
    try testing.expect(list.len == 4);
    try testing.expect(list.last == &node5);

    // Test popFirst
    const popped_first_node = list.popFirst();
    try testing.expect(popped_first_node == &node3);
    try testing.expect(list.len == 3);
    try testing.expect(list.first == &node1);

    // Test remove
    list.remove(&node4);
    try testing.expect(list.len == 2);
    try testing.expect(node1.next == &node5);
    try testing.expect(node5.prev == &node1);

    // Test concatByMoving
    var list2 = L{};
    var node6 = L.Node{ .data = 60 };
    var node7 = L.Node{ .data = 70 };
    list2.append(&node6);
    list2.append(&node7);
    list.concatByMoving(&list2);
    try testing.expect(list.len == 4);
    try testing.expect(list2.len == 0);
    try testing.expect(list.last == &node7);
    try testing.expect(list2.first == null);
    try testing.expect(list2.last == null);

    // Traverse forwards
    {
        var it = list.first;
        const expected_data = [_]u32{ 10, 50, 60, 70 };
        var index: usize = 0;
        while (it) |node| : (it = node.next) {
            try testing.expect(node.data == expected_data[index]);
            index += 1;
        }
    }

    // Traverse backwards
    {
        var it = list.last;
        const expected_data = [_]u32{ 70, 60, 50, 10 };
        var index: usize = 0;
        while (it) |node| : (it = node.prev) {
            try testing.expect(node.data == expected_data[index]);
            index += 1;
        }
    }
}

// These tests are copied from the Zig standard library tests for SinglyLinkedList and DoublyLinkedList.
// To ensure that our implementation passes the same tests.
//
test "ZIG STD TEST: basic SinglyLinkedList test" {
    const std = @import("std");
    const testing = std.testing;

    const L = SinglyLinkedList(u32);
    var list = L{};

    try testing.expect(list.len() == 0);

    var one = L.Node{ .data = 1 };
    var two = L.Node{ .data = 2 };
    var three = L.Node{ .data = 3 };
    var four = L.Node{ .data = 4 };
    var five = L.Node{ .data = 5 };

    list.prepend(&two); // {2}
    two.insertAfter(&five); // {2, 5}
    list.prepend(&one); // {1, 2, 5}
    two.insertAfter(&three); // {1, 2, 3, 5}
    three.insertAfter(&four); // {1, 2, 3, 4, 5}

    try testing.expect(list.len() == 5);

    // Traverse forwards.
    {
        var it = list.first;
        var index: u32 = 1;
        while (it) |node| : (it = node.next) {
            try testing.expect(node.data == index);
            index += 1;
        }
    }

    _ = list.popFirst(); // {2, 3, 4, 5}
    _ = list.remove(&five); // {2, 3, 4}
    _ = two.removeNext(); // {2, 4}

    try testing.expect(list.first.?.data == 2);
    try testing.expect(list.first.?.next.?.data == 4);
    try testing.expect(list.first.?.next.?.next == null);

    L.Node.reverse(&list.first);

    try testing.expect(list.first.?.data == 4);
    try testing.expect(list.first.?.next.?.data == 2);
    try testing.expect(list.first.?.next.?.next == null);
}

test "ZIG STD TEST: basic DoublyLinkedList test" {
    const std = @import("std");
    const testing = std.testing;

    const L = DoublyLinkedList(u32);
    var list = L{};

    var one = L.Node{ .data = 1 };
    var two = L.Node{ .data = 2 };
    var three = L.Node{ .data = 3 };
    var four = L.Node{ .data = 4 };
    var five = L.Node{ .data = 5 };

    list.append(&two); // {2}
    list.append(&five); // {2, 5}
    list.prepend(&one); // {1, 2, 5}
    list.insertBefore(&five, &four); // {1, 2, 4, 5}
    list.insertAfter(&two, &three); // {1, 2, 3, 4, 5}

    // Traverse forwards.
    {
        var it = list.first;
        var index: u32 = 1;
        while (it) |node| : (it = node.next) {
            try testing.expect(node.data == index);
            index += 1;
        }
    }

    // Traverse backwards.
    {
        var it = list.last;
        var index: u32 = 1;
        while (it) |node| : (it = node.prev) {
            try testing.expect(node.data == (6 - index));
            index += 1;
        }
    }

    _ = list.popFirst(); // {2, 3, 4, 5}
    _ = list.pop(); // {2, 3, 4}
    list.remove(&three); // {2, 4}

    try testing.expect(list.first.?.data == 2);
    try testing.expect(list.last.?.data == 4);
    try testing.expect(list.len == 2);
}

test "ZIG STD TEST: DoublyLinkedList concatenation" {
    const std = @import("std");
    const testing = std.testing;

    const L = DoublyLinkedList(u32);
    var list1 = L{};
    var list2 = L{};

    var one = L.Node{ .data = 1 };
    var two = L.Node{ .data = 2 };
    var three = L.Node{ .data = 3 };
    var four = L.Node{ .data = 4 };
    var five = L.Node{ .data = 5 };

    list1.append(&one);
    list1.append(&two);
    list2.append(&three);
    list2.append(&four);
    list2.append(&five);

    list1.concatByMoving(&list2);

    try testing.expect(list1.last == &five);
    try testing.expect(list1.len == 5);
    try testing.expect(list2.first == null);
    try testing.expect(list2.last == null);
    try testing.expect(list2.len == 0);

    // Traverse forwards.
    {
        var it = list1.first;
        var index: u32 = 1;
        while (it) |node| : (it = node.next) {
            try testing.expect(node.data == index);
            index += 1;
        }
    }

    // Traverse backwards.
    {
        var it = list1.last;
        var index: u32 = 1;
        while (it) |node| : (it = node.prev) {
            try testing.expect(node.data == (6 - index));
            index += 1;
        }
    }

    // Swap them back, this verifies that concatenating to an empty list works.
    list2.concatByMoving(&list1);

    // Traverse forwards.
    {
        var it = list2.first;
        var index: u32 = 1;
        while (it) |node| : (it = node.next) {
            try testing.expect(node.data == index);
            index += 1;
        }
    }

    // Traverse backwards.
    {
        var it = list2.last;
        var index: u32 = 1;
        while (it) |node| : (it = node.prev) {
            try testing.expect(node.data == (6 - index));
            index += 1;
        }
    }
}
