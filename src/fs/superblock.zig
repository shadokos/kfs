const std = @import("std");
const Inode = @import("inode.zig");
const Partition = @import("../device/block/partition.zig");
const dev_t = @import("../device/types.zig").dev_t;

block_size: usize,
fragment_size: usize,
blocks: BlockCount,
free_blocks: BlockCount,
reserved_blocks: BlockCount,
files: FileCount,
free_files: FileCount,
reserved_files: FileCount,
fsid: ?usize,
flags: Flags,
max_name: usize,

uuid: ?UUID,

partition: *Partition,
vtable: *const VTable,
cache: InodeCache,

pub const FileCount = usize;
pub const BlockCount = usize;
pub const Flags = struct {
    read_only: bool,
    no_suid: bool,
};
pub const UUID = u128;

pub const InodeCache = std.AutoHashMap(Inode.Ino, *Inode);

const Self = @This();

pub const Error = struct {
    pub const load_inode = error{
        ENOMEM,
        EIO,
        EPERM,
        ENODEV,
        EBUSY,
    };
    pub const release_inode = error{};
    pub const allocate = error{};
    pub const free = error{};
    pub const get_root = load_inode;
    pub const create_inode = error{
        ENOMEM,
        EIO,
        EPERM,
        ENODEV,
        EBUSY,
        ENOSPC,
    };
};

pub const TypeSpecificParams = union(Inode.Mode.Type) {
    Block: dev_t,
    Character: dev_t,
    Directory: struct {
        parent_ino: *Inode,
    },
    Fifo: void,
    Regular: void,
    Link: []const u8,
    Socket: void,
};

pub const VTable = struct {
    load_inode: *const fn (*Self, Inode.Ino) Error.load_inode!*Inode,
    release_inode: *const fn (*Self, *Inode) Error.release_inode!void,
    get_root: *const fn (*Self) Error.get_root!*Inode,
    create_inode: *const fn (
        self: *Self,
        uid: Inode.Uid,
        gid: Inode.Gid,
        mode: Inode.Mode,
        type_specific: TypeSpecificParams,
    ) Error.create_inode!*Inode,
};

pub fn get_root(self: *Self) Error.get_root!*Inode {
    const ret = try self.vtable.get_root(self);
    return ret;
}

pub fn retrieve_inode(self: *Self, ino: Inode.Ino) Error.load_inode!*Inode {
    std.log.debug("retrieve ino: {}", .{ino});
    if (self.cache.get(ino)) |inode| {
        return inode.get_ref();
    } else {
        const ret = try self.vtable.load_inode(self, ino);
        errdefer self.vtable.release_inode(self, ret) catch {}; // todo: ignore error?
        self.cache.put(ino, ret) catch return error.ENOMEM;
        return ret.get_ref();
    }
}

pub fn create_inode(
    self: *Self,
    uid: Inode.Uid,
    gid: Inode.Gid,
    mode: Inode.Mode,
    type_specific: TypeSpecificParams,
) Error.create_inode!*Inode {
    const inode = try self.vtable.create_inode(self, uid, gid, mode, type_specific);
    errdefer self.vtable.release_inode(self, inode) catch {}; // todo: ignore error?
    std.log.debug("create ino: {}", .{inode.ino});
    self.cache.put(inode.ino, inode) catch return error.ENOMEM;
    return inode.get_ref();
}

pub fn flush_all(self: *Self) Inode.Error.flush!void {
    var it = self.cache.iterator();
    while (it.next()) |entry| {
        try entry.value_ptr.*.flush();
    }
}

pub fn release_inode(self: *Self, inode: *Inode) Error.release_inode!void {
    _ = self.cache.remove(inode.ino);
    try self.vtable.release_inode(self, inode);
}

// todo: should we fail?
pub fn release_all(self: *Self) Error.release_inode!void {
    var it = self.cache.iterator();
    while (it.next()) |entry| {
        try self.release_inode(entry.value_ptr.*);
        _ = self.cache.remove(entry.key_ptr.*);
        it = self.cache.iterator();
    }
}
