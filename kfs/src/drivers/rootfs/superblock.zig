const std = @import("std");
const Inode = @import("../../fs/inode.zig");
const Superblock = @import("../../fs/superblock.zig");
const Errno = @import("../../errno.zig").Errno;
const memory = @import("../../memory.zig");
const RootInode = @import("root_inode.zig");

const logger = std.log.scoped(.rootfs_superblock);

pub var instance: Superblock = .{
    .block_size = 4096,
    .fragment_size = 4096,
    .blocks = 0,
    .free_blocks = 0,
    .reserved_blocks = 0,
    .files = 0,
    .free_files = 0,
    .reserved_files = 0,
    .fsid = null,
    .max_name = 256,
    .flags = .{
        .read_only = true,
        .no_suid = false,
    },
    .uuid = null,
    .partition = undefined,
    .vtable = &superblock_vtable,
    .cache = Superblock.InodeCache.init(memory.smallAlloc.allocator()),
};

const superblock_vtable: Superblock.VTable = .{
    .get_root = &get_root,
    .load_inode = undefined,
    .release_inode = undefined,
    .create_inode = undefined,
};

pub fn get_root(_: *Superblock) Superblock.Error.get_root!*Inode {
    return &RootInode.instance;
}

const device_inode_vtable: Inode.VTable = .{
    .open = null,
    .lookup = null,
    .link = &Inode.VTable.Generic.link,
    .unlink = &Inode.VTable.Generic.unlink,
};
