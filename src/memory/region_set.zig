const ft = @import("../ft/ft.zig");
const paging = @import("paging.zig");

const Region = @import("regions.zig").Region;

pub const RegionSet = struct {
    size: usize = 0,
    list: ?*Region = null,
    const Self = @This();

    pub fn clear(self: *Self) !void {
        while (self.list) |first| {
            try self.destroy_region(first);
        }
    }

    pub fn clone(self: Self) !Self {
        var ret = Self{};
        var current = self.list;
        errdefer ret.clear() catch unreachable;
        while (current) |n| : (current = n.next) {
            _ = try ret.create_region(n.*);
        }
        return ret;
    }

    pub fn create_region(self: *Self, content: Region) !*Region {
        const new_region = try Region.create();
        new_region.* = content;
        new_region.prev = null;
        new_region.next = null;
        self.size += 1;
        if (self.list) |first| {
            first.prev = new_region;
            new_region.next = first;
        }
        self.list = new_region;
        new_region.prev = null;
        return new_region;
    }

    pub fn destroy_region(self: *Self, to_remove: *Region) !void {
        if (to_remove.prev) |prev| {
            prev.next = to_remove.next;
        } else {
            self.list = to_remove.next;
        }
        if (to_remove.next) |next| {
            next.prev = to_remove.prev;
        }
        self.size -= 1;
        try Region.destroy(to_remove);
    }

    pub fn copy(self: *Self) !Self {
        var ret = Self{};
        var head: ?*Region = self.list;
        while (head) |node| : (head = node.next) {
            _ = try ret.create_region(node.*);
        }
        return ret;
    }

    pub fn find(self: *Self, ptr: paging.VirtualPtr) ?*Region {
        var current = self.list;
        const page: usize = @intFromPtr(ptr) / paging.page_size;
        return while (current) |node| : (current = node.next) {
            if (page >= node.begin and page < node.begin + node.len) {
                break node;
            }
        } else null;
    }
};
