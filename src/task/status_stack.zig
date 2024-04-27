const ft = @import("../ft/ft.zig");
const task = @import("task.zig");
const TaskDescriptor = task.TaskDescriptor;
const scheduler = @import("scheduler.zig");
const Status = @import("status_informations.zig").Status;
const task_set = @import("task_set.zig");
const logger = @import("../ft/ft.zig").log.scoped(.status_stack);

pub const StatusStack = struct {
    lists: [3]?*Node = .{ null, null, null },

    pub const Node = struct {
        next: ?*Node = null,
        prev: ?*Node = null,
    };

    const Self = @This();

    pub fn add(self: *Self, node: *Node, transition: Status.Transition) void {
        self.remove(node);

        const list = &self.lists[@intFromEnum(transition)];
        if (list.*) |l| {
            l.prev = node;
            node.next = l;
        }
        list.* = node;
    }

    pub fn remove(self: *Self, node: *Node) void {
        if (node.next) |n| {
            n.prev = node.prev;
        }
        if (node.prev) |p| {
            p.next = node.next;
        } else {
            inline for (self.lists[0..]) |*l| {
                if (l.* == node) {
                    l.* = node.next;
                    break;
                }
            }
        }

        node.* = .{};
    }

    pub fn pop(self: *Self, transition: Status.Transition) ?*Node {
        if (self.lists[@intFromEnum(transition)]) |ret| {
            self.remove(ret);
            return ret;
        } else return null;
    }

    pub fn top(self: Self, transition: Status.Transition) ?*Node {
        return self.lists[@intFromEnum(transition)];
    }
};
