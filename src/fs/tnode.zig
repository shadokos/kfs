const std = @import("std");
const Inode = @import("inode.zig");
const Cache = @import("../memory/object_allocators/slab/cache.zig").Cache;
const memory = @import("../memory.zig");
const logger = std.log.scoped(.tnode);

name: []const u8,
inode: *Inode,
mountpoint: ?MountPoint = null,
sibling_node: std.DoublyLinkedList.Node = .{},
parent: *Self,
refs: usize = 0,

const InodeNamePair = struct {
    inode: *Inode,
    name: []const u8,
    pub const Context = struct {
        pub fn hash(_: @This(), key: InodeNamePair) u64 {
            var hasher: std.hash.Wyhash = std.hash.Wyhash.init(0);
            hasher.update(&std.mem.toBytes(@as(usize, @intFromPtr(key.inode))));
            hasher.update(key.name);
            return hasher.final();
        }
        pub fn eql(_: @This(), l: InodeNamePair, r: InodeNamePair) bool {
            return l.inode == r.inode and std.mem.eql(u8, l.name, r.name);
        }
    };
};

const MountPoint = struct { shadowed_inode: *Inode };

const TnodeCache = std.HashMapUnmanaged(
    InodeNamePair,
    *Self,
    InodeNamePair.Context,
    std.hash_map.default_max_load_percentage,
);

var tnodeCache: TnodeCache = .empty;

const Self = @This();
var cache: *Cache = undefined;

pub fn init_cache() !void {
    cache = try memory.globalCache.create(
        "tnode",
        memory.directPageAllocator.page_allocator(),
        @sizeOf(Self),
        @alignOf(Self),
        6,
    );
}

pub fn create() !*Self {
    return try cache.allocator().create(Self);
}

pub fn destroy(self: *Self) void {
    cache.allocator().destroy(self);
}

pub fn get_ref(self: *Self) *Self {
    std.log.debug("acquiring Tnode {s} {}", .{ self.name, self.refs });
    self.refs += 1;
    return self;
}

pub fn release(self: *Self) void {
    std.log.debug("releasing Tnode {s} {}", .{ self.name, self.refs });
    std.debug.assert(self.refs > 0);
    self.refs -= 1;
    if (self.refs == 0) {
        std.log.debug("evicted", .{});
        std.debug.assert(self.mountpoint == null);
        self.inode.release();
        self.parent.inode.type_specific.Directory.children.remove(&self.sibling_node);
        self.parent.release();
        if (!tnodeCache.remove(.{ .inode = self.parent.inode, .name = self.name }))
            @panic("todo");
        destroy(self);
    }
}

pub fn mount(self: *Self, inode: *Inode) void {
    std.log.debug("mount tnode: {*}", .{self});
    if (self.mountpoint) |_| {
        @panic("todo: already a mountpoint");
    }
    self.mountpoint = .{
        .shadowed_inode = self.inode,
    };
    self.inode = inode.get_ref();
}

pub fn unmount(self: *Self) void {
    if (self.mountpoint) |*mountpoint| {
        self.inode.release();
        self.inode = mountpoint.shadowed_inode;
        self.mountpoint = null;
    } else {
        @panic("todo: not a mountpoin");
    }
}

pub fn lookup(self: *Self, name: []const u8) ?*Self {
    if (std.mem.eql(u8, name, ".")) {
        return self.get_ref();
    } else if (std.mem.eql(u8, name, "..")) {
        return self.parent.get_ref();
    } else if (tnodeCache.get(.{ .inode = self.inode, .name = name })) |tnode| {
        std.log.debug("cache hit {*} {s}", .{ self.inode, name });
        return tnode.get_ref();
    } else if (self.inode.lookup(name) catch @panic("todo")) |inode| {
        std.log.debug("cache miss {*} {s}", .{ self.inode, name });
        const tnode = create() catch @panic("todo");
        errdefer destroy(tnode);
        const owned_name = memory.smallAlloc.allocator().dupe(u8, name) catch @panic("todo");
        errdefer memory.smallAlloc.allocator().free(owned_name);
        tnode.* = .{
            .inode = inode,
            .name = owned_name,
            .parent = self.get_ref(),
            .refs = 1,
        };
        self.inode.type_specific.Directory.children.append(&tnode.sibling_node);
        tnodeCache.put(
            memory.bigAlloc.allocator(),
            .{
                .inode = self.inode,
                .name = owned_name,
            },
            tnode,
        ) catch @panic("todo");
        return tnode;
    } else {
        return null;
    }
}
