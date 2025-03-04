const ft = @import("ft");
const paging = @import("paging.zig");
const memory = @import("../memory.zig");
const globalCache = &memory.globalCache;
const Cache = @import("object_allocators/slab/cache.zig").Cache;
const Region = @import("regions.zig").Region;

pub const RegionSet = struct {
    list: ListType = .{},

    const ListType = ft.DoublyLinkedList(Region);
    var nodeCache: ?*Cache = null;
    const Self = @This();

    pub fn init_cache() !void {
        nodeCache = try globalCache.create(
            "regions",
            memory.directPageAllocator.page_allocator(),
            @sizeOf(ListType.Node),
            @alignOf(ListType.Node),
            4,
        );
    }

    pub fn clear(self: *Self) !void {
        while (self.list.first) |first| {
            try self.destroy_region(&first.data);
        }
    }

    pub fn clone(self: Self) !Self {
        var ret = Self{};
        errdefer ret.clear() catch unreachable;

        var head = self.list.first;
        while (head) |node| : (head = node.next) {
            _ = try ret.create_region(node.data);
        }

        return ret;
    }

    pub fn create_region(self: *Self, content: Region) !*Region {
        const new_node: *ListType.Node = if (nodeCache) |c|
            @ptrCast(try c.alloc_one())
        else
            @panic("region cache is not initialized");
        new_node.data = content;
        self.list.append(new_node);
        return &new_node.data;
    }

    pub fn destroy_region(self: *Self, to_remove: *Region) !void {
        const node: *ListType.Node = @fieldParentPtr("data", to_remove);
        self.list.remove(node);
        if (nodeCache) |c| {
            return c.free(@ptrCast(node));
        } else {
            @panic("region cache is not initialized");
        }
    }

    pub fn find(self: *Self, ptr: paging.VirtualPtr) ?*Region {
        const page: usize = @intFromPtr(ptr) / paging.page_size;
        var current = self.list.first;
        return while (current) |node| : (current = node.next) {
            if (page >= node.data.begin and page < node.data.begin + node.data.len) {
                break &node.data;
            }
        } else null;
    }
};
