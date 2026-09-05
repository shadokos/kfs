const std = @import("std");
const SuperBlock = @import("superblock.zig");
const File = @import("file.zig");
const Tnode = @import("tnode.zig");
const dev_t = @import("../device/types.zig").dev_t;
const Errno = @import("../errno.zig").Errno;
const logger = std.log.scoped(.inode);
const SlabCache = @import("../memory/object_allocators/slab/cache.zig").Cache;
const memory = @import("../memory.zig");

superblock: *SuperBlock,
ino: Ino,
hard_links: u16,
size: u64,
uid: Uid,
gid: Gid,
mode: Mode,
type_specific: TypeSpecificData,
refs: usize = 0,

vtable: *const VTable,
// time access, edited, status

var cache: *SlabCache = undefined;

pub const Uid = u16;
pub const Gid = u16;

const Self = @This();

pub const Ino = usize;

pub const DirEnt = struct {
    inode: Ino,
    type: Mode.Type,
    name_len: usize,
    name: [256]u8,
};

pub const TypeSpecificData = union(Mode.Type) {
    Block: dev_t,
    Character: dev_t,
    Directory: struct {
        children: std.DoublyLinkedList = .{},
    },
    Fifo: ?struct {
        buffer: []u8,
        tail: usize,
        head: usize,
    },
    Regular: void,
    Link: []const u8,
    Socket: void,
};

pub const Error = struct {
    pub const open = error{ ENOMEM, ENXIO, EIO, EPERM };
    pub const link = error{
        EIO,
        ENODEV,
        EBUSY,
        EPERM,
        ENOSPC,
        ENOMEM,
        EEXIST,
    };
    pub const unlink = error{
        EIO,
        ENODEV,
        EBUSY,
        EPERM,
        ENOSPC,
        ENOMEM,
        ENOENT,
    };
    pub const lookup = SuperBlock.Error.load_inode || error{ENOTDIR};
    pub const truncate = error{
        EIO,
        ENODEV,
        EBUSY,
        EPERM,
        ENOSPC,
        ENOMEM,
    };
};

pub const VTable = struct {
    open: ?*const fn (*Self, file: *File) Error.open!void = null,
    link: ?*const fn (*Self, name: []const u8, *Self) Error.link!void = null,
    unlink: ?*const fn (*Self, name: []const u8) Error.unlink!void = null,
    lookup: ?*const fn (*Self, name: []const u8) Error.lookup!?*Self = null,
    truncate: ?*const fn (*Self, new_size: u64) Error.truncate!void = null,

    pub const Generic = struct {
        pub fn lookup(self: *Self, name: []const u8) Error.lookup!?*Self {
            if (self.mode.type != .Directory) {
                return error.ENOTDIR;
            }
            var file = self.open() catch |e| return @errorCast(e);
            var dirent: File.DirEnt = undefined;
            while (try file.readdir(&dirent)) {
                if (std.mem.eql(u8, dirent.name[0..dirent.name_len], name)) {
                    return self.superblock.retrieve_inode(dirent.inode);
                }
            }
            return null;
        }
        pub fn link(_: *Self, _: []const u8, _: *Self) Error.link!void {
            return error.EPERM;
        }
        pub fn unlink(_: *Self, _: []const u8) Error.unlink!void {
            return error.EPERM;
        }
    };
};

// todo: common definition with ext2
pub const Mode = packed struct {
    other: Perm = .{},
    group: Perm = .{},
    owner: Perm = .{},
    restricted_deletion: bool = false,
    sgid: bool = false,
    suid: bool = false,
    type: Type,

    pub const Perm = packed struct(u3) {
        read: bool = false,
        write: bool = false,
        execute: bool = false,
    };
    pub const Type = enum(u4) {
        Block = 0x1,
        Character = 0x2,
        Directory = 0x4,
        Fifo = 0x6,
        Regular = 0x8,
        Link = 0xa,
        Socket = 0xc,
    };
};

fn call_or_panic(self: *Self, comptime method: std.meta.FieldEnum(VTable), args: anytype) @typeInfo(@typeInfo(@typeInfo(std.meta.fieldInfo(VTable, method).type).optional.child).pointer.child).@"fn".return_type.? {
    if (@field(self.vtable, @tagName(method))) |f| {
        return @call(.auto, f, .{self} ++ args);
    } else {
        @panic(@tagName(method) ++ " not implemented");
    }
}

pub fn init_cache() !void {
    cache = try memory.globalCache.create(
        "inode",
        memory.directPageAllocator.page_allocator(),
        @sizeOf(Self),
        @alignOf(Self),
        6,
    );
}

pub fn create() !*Self {
    return cache.allocator().create(Self) catch error.ENOMEM;
}

pub fn destroy(self: *Self) void {
    cache.allocator().destroy(self);
}

pub fn open(self: *Self) Error.open!*File {
    const ret = try File.create();
    errdefer ret.destroy();
    if (self.mode.type == .Fifo) {
        try @import("pipe.zig").open(self, ret);
    } else if (self.mode.type == .Block) {
        try @import("block.zig").open(self, ret);
    } else {
        try self.call_or_panic(.open, .{ret});
    }
    return ret;
}

pub fn lookup(self: *Self, name: []const u8) Error.lookup!?*Self {
    return self.call_or_panic(.lookup, .{name});
}

pub fn truncate(self: *Self, new_size: u64) Error.truncate!void {
    return self.call_or_panic(.truncate, .{new_size});
}

pub fn link(self: *Self, name: []const u8, other: *Self) Error.link!void {
    return self.call_or_panic(.link, .{ name, other });
}

pub fn unlink(self: *Self, name: []const u8) Error.unlink!void {
    return self.call_or_panic(.unlink, .{name});
}

pub fn get_ref(self: *Self) *Self {
    logger.debug("acquiring Inode {} {}", .{ self.ino, self.refs });
    self.refs += 1;
    return self;
}

pub fn release(self: *Self) void {
    logger.debug("releasing Inode {} {}", .{ self.ino, self.refs });
    std.debug.assert(self.refs > 0);
    self.refs -= 1;
    if (self.refs == 0) {
        self.superblock.release_inode(self) catch |e| {
            logger.warn("Error while releasing inode {*} {s}", .{ self, @errorName(e) });
        };
    }
}
