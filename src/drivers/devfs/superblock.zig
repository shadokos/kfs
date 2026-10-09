const std = @import("std");
const Inode = @import("../../fs/inode.zig");
const Partition = @import("../../device/block/partition.zig");
const blk = @import("../../device/block/block.zig");
const Superblock = @import("../../fs/superblock.zig");
const VfsInode = @import("../../fs/inode.zig");
const Errno = @import("../../errno.zig").Errno;
const File = @import("../../fs/file.zig");
const block_registry = @import("../../device/block/registry.zig");
const char_registry = @import("../../device/char/registry.zig");
const DeviceId = @import("../../device/types.zig").dev_t;
const memory = @import("../../memory.zig");
const RootInode = @import("root_inode.zig");

const logger = std.log.scoped(.devfs_superblock);

pub const Ino = packed struct(Inode.Ino) {
    device: DeviceId,
    type: Type,
    _unused: u15 = undefined,

    pub const Type = enum(u1) {
        Character,
        Block,
    };
};

pub var instance = init();

pub fn init() Superblock {
    return .{
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
}

const superblock_vtable: Superblock.VTable = .{
    .get_root = &get_root,
    .load_inode = &load_inode,
    .release_inode = &release_inode,
    .create_inode = undefined,
};

pub fn load_inode(superblock: *Superblock, vfs_ino: VfsInode.Ino) Superblock.Error.load_inode!*Inode {
    const ino: Ino = @bitCast(vfs_ino);
    const ret = try Inode.create();
    ret.* = .{
        .uid = 0,
        .gid = 0,
        .hard_links = 1,
        .ino = vfs_ino,
        .mode = .{
            .type = switch (ino.type) {
                .Character => .Character,
                .Block => .Block,
            },
            .other = .{
                .read = true,
            },
        },
        .refs = 1,
        .size = 0,
        .superblock = superblock,
        .type_specific = switch (ino.type) {
            .Character => .{ .Character = ino.device },
            .Block => .{ .Block = ino.device },
        },
        .vtable = &device_inode_vtable,
    };
    return ret;
}

pub fn release_inode(_: *Superblock, inode: *Inode) Superblock.Error.release_inode!void {
    if (inode != &RootInode.instance) {
        inode.destroy();
    }
}

pub fn get_root(_: *Superblock) Superblock.Error.get_root!*Inode {
    return &RootInode.instance;
}

const device_inode_vtable: Inode.VTable = .{
    .open = null,
    .lookup = null,
    .link = &Inode.VTable.Generic.link,
    .unlink = &Inode.VTable.Generic.unlink,
};
