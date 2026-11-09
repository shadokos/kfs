const std = @import("std");
const Inode = @import("../../fs/inode.zig");
const Superblock = @import("superblock.zig");
const Errno = @import("../../errno.zig").Errno;
const File = @import("../../fs/file.zig");

const logger = std.log.scoped(.devfs_superblock);

pub var instance: Inode = .{
    .superblock = &Superblock.instance,
    .ino = 0,
    .hard_links = 0,
    .size = 0,
    .uid = 0,
    .gid = 0,
    .mode = .{
        .other = .{
            .read = true,
            .execute = true,
        },
        .type = .Directory,
    },
    .type_specific = .{ .Directory = .{} },
    .refs = 1,
    .vtable = &root_vtable,
};

fn root_open(_: *Inode, _: *File) Inode.Error.open!void {
    return Errno.EPERM;
}

fn root_lookup(_: *Inode, _: []const u8) Inode.Error.lookup!?*Inode {
    return null;
}

const root_vtable: Inode.VTable = .{
    .open = &root_open,
    .lookup = &root_lookup,
    .link = &Inode.VTable.Generic.link,
    .unlink = &Inode.VTable.Generic.unlink,
};