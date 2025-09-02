const std = @import("std");
const paging = @import("paging.zig");
const memory = @import("../memory.zig");
const globalCache = &memory.globalCache;
const Cache = @import("object_allocators/slab/cache.zig").Cache;
const Region = @import("regions.zig").Region;

// todo: use a binary search tree or a skiplist (We want fast insertion, removal, find and in order traversal),
// the complexity of the in order iterator is currently O(N^2) this must be changed
pub const RegionSet = struct {
    list: ListType = .{},

    const ListType = std.DoublyLinkedList;
    pub const ListNode = struct {
        node: std.DoublyLinkedList.Node,
        data: Region,
    };

    pub const RangeIterator = struct {
        lower_bound: usize,
        upper_bound: usize,
        region_set: *RegionSet,

        pub fn next(self: *RangeIterator) ?*Region {
            if (self.lower_bound >= self.upper_bound) {
                return null;
            }
            var current = self.region_set.list.first;
            var min: ?*Region = null;
            while (current) |node| : (current = node.next) {
                const list_node: *ListNode = @fieldParentPtr("node", node);
                if (list_node.data.begin + list_node.data.len > self.lower_bound and
                    list_node.data.begin < self.upper_bound and
                    (min == null or list_node.data.begin < min.?.begin))
                {
                    min = &list_node.data;
                }
            }
            if (min) |min_region| {
                self.lower_bound = min_region.begin + min_region.len;
            }
            return min;
        }
    };

    var nodeCache: ?*Cache = null;
    const Self = @This();

    pub fn init_cache() !void {
        nodeCache = try globalCache.create(
            "regions",
            memory.directPageAllocator.page_allocator(),
            @sizeOf(ListNode),
            @alignOf(ListNode),
            4,
        );
    }

    pub fn clear(self: *Self) !void {
        while (self.list.first) |first| {
            const list_node: *ListNode = @fieldParentPtr("node", first);
            self.remove_region(&list_node.data);
            try destroy_region(&list_node.data);
        }
    }

    pub fn clone(self: Self) !Self {
        var ret = Self{};
        errdefer ret.clear() catch unreachable;

        var head = self.list.first;
        while (head) |node| : (head = node.next) {
            const list_node: *ListNode = @fieldParentPtr("node", node);
            const new_region = try create_region();
            new_region.* = list_node.data;
            ret.add_region(new_region);
        }

        return ret;
    }

    pub fn create_region() !*Region {
        const new_node: *ListNode = if (nodeCache) |c|
            @ptrCast(try c.alloc_one())
        else
            @panic("region cache is not initialized");
        new_node.data = .{};
        return &new_node.data;
    }

    pub fn destroy_region(to_remove: *Region) !void {
        const node: *ListNode = @fieldParentPtr("data", to_remove);
        if (nodeCache) |c| {
            return c.free(@ptrCast(node)); // todo: maybe panic since this is never supposed to fail
        } else {
            @panic("region cache is not initialized");
        }
    }

    pub fn add_region(self: *Self, region: *Region) void {
        const list_node: *ListNode = @fieldParentPtr("data", region);
        self.list.append(&list_node.node);
    }

    pub fn remove_region(self: *Self, region: *Region) void {
        const list_node: *ListNode = @fieldParentPtr("data", region);
        self.list.remove(&list_node.node);
    }

    pub fn find(self: *Self, page: usize) ?*Region {
        return self.find_any_in_range(page, 1);
    }

    pub fn find_any_in_range(self: *Self, page: usize, npage: usize) ?*Region {
        var current = self.list.first;
        return while (current) |node| : (current = node.next) {
            const list_node: *ListNode = @fieldParentPtr("node", node);
            if (page + npage > list_node.data.begin and page < list_node.data.begin + list_node.data.len) {
                break &list_node.data;
            }
        } else null;
    }

    pub fn get_range_iterator(self: *Self, page: usize, npage: usize) RangeIterator {
        return .{
            .lower_bound = page,
            .upper_bound = page + npage,
            .region_set = self,
        };
    }
};
