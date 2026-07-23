const std = @import("std");
const SuperBlock = @import("superblock.zig");
const File = @import("file.zig");
const Tnode = @import("tnode.zig");
const dev_t = @import("../device/types.zig").dev_t;
const Errno = @import("../errno.zig").Errno;
const logger = std.log.scoped(.inode);

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
    Fifo: void,
    Regular: void,
    Link: []const u8,
    Socket: void,
};

pub const Error = struct {
    pub const flush = error{
        EIO,
        ENODEV,
        EBUSY,
        EPERM,
        ENOMEM,
    };
    pub const open = error{ENOMEM};
    pub const lookup = SuperBlock.Error.load_inode;
    pub const truncate = error{
        EIO,
        ENODEV,
        EBUSY,
        EPERM,
        ENOSPC,
        ENOMEM,
    };
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
    pub const preaddir = error{
        EBUSY,
        EIO,
        ENODEV,
        ENOMEM,
        EPERM,
    };
    pub const pread = error{
        EBUSY,
        EIO,
        ENODEV,
        ENOMEM,
        EPERM,
        ENXIO,
    };
    pub const pwrite = error{
        EBUSY,
        EIO,
        ENODEV,
        ENOMEM,
        EPERM,
        ENOSPC,
    };
};

pub const VTable = struct {
    flush: *const fn (*Self) Error.flush!void,
    open: *const fn (*Self) Error.open!*File = &Generic.open,
    lookup: *const fn (*Self, name: []const u8) Error.lookup!?*Self = &Generic.lookup,
    truncate: *const fn (*Self, new_size: u64) Error.truncate!void,
    link: *const fn (*Self, name: []const u8, *Self) Error.link!void,
    unlink: *const fn (*Self, name: []const u8) Error.unlink!void,
    pread: *const fn (*Self, pos: u64, buffer: []u8) Error.pread!usize,
    preaddir: *const fn (self: *Self, pos: u64, dst: *DirEnt) Error.preaddir!usize,
    pwrite: *const fn (*Self, pos: u64, buffer: []const u8) Error.pwrite!usize,
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

pub fn flush(self: *Self) Error.flush!void {
    return self.vtable.flush(self);
}

pub fn open(self: *Self) Error.open!*File {
    if (self.mode.type == .Block) {}
    return self.vtable.open(self);
}

pub fn lookup(self: *Self, name: []const u8) Error.lookup!?*Self {
    return self.vtable.lookup(self, name);
}

pub fn link(self: *Self, name: []const u8, other: *Self) Error.link!void {
    return self.vtable.link(self, name, other);
}

pub fn unlink(self: *Self, name: []const u8) Error.unlink!void {
    return self.vtable.unlink(self, name);
}

pub fn truncate(self: *Self, new_size: u64) Error.truncate!void {
    return self.vtable.truncate(self, new_size);
}

pub fn pread(self: *Self, pos: u64, buffer: []u8) Error.pread!usize {
    if (self.mode.type == .Block) {
        const BlockSize = @import("../device/block/block.zig").STANDARD_BLOCK_SIZE;
        const part = @import("../device/block/registry.zig").get_partition(self.type_specific.Block) orelse return Errno.EIO;
        if (pos % BlockSize != 0 or buffer.len % BlockSize != 0 or pos > std.math.maxInt(usize)) {
            return Errno.ENXIO;
        }
        part.read(@intCast(pos / BlockSize), buffer.len / BlockSize, buffer) catch {
            return Errno.EIO;
        };
        return buffer.len; // todo
    } else {
        return self.vtable.pread(self, pos, buffer);
    }
}

pub fn pwrite(self: *Self, pos: u64, buffer: []const u8) Error.pwrite!usize {
    return self.vtable.pwrite(self, pos, buffer);
}

pub fn preaddir(self: *Self, pos: u64, dst: *DirEnt) Error.preaddir!usize {
    return self.vtable.preaddir(self, pos, dst);
}

pub fn get_ref(self: *Self) *Self {
    std.log.debug("acquiring Inode {} {}", .{ self.ino, self.refs });
    self.refs += 1;
    return self;
}

pub fn release(self: *Self) void {
    std.log.debug("releasing Inode {} {}", .{ self.ino, self.refs });
    std.debug.assert(self.refs > 0);
    self.refs -= 1;
    if (self.refs == 0) {
        self.superblock.release_inode(self) catch |e| {
            logger.warn("Error while releasing inode {*} {s}", .{ self, @errorName(e) });
        };
    }
}

const Generic = struct {
    pub fn open(self: *Self) Error.open!*File {
        const ret = try File.create();
        ret.* = File{
            .inode = self.get_ref(),
            .refs = 1,
        };
        return ret;
    }

    pub fn lookup(self: *Self, name: []const u8) Error.lookup!?*Self {
        var file = try self.open();
        var dirent: File.DirEnt = undefined;
        while (try file.readdir(&dirent)) {
            if (std.mem.eql(u8, dirent.name[0..dirent.name_len], name)) {
                return self.superblock.retrieve_inode(dirent.inode);
            }
        }
        return null;
    }
};
