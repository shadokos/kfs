const std = @import("std");
const Inode = @import("../../fs/inode.zig");
const Partition = @import("../../device/block/partition.zig");
const blk = @import("../../device/block/block.zig");
const Superblock = @import("superblock.zig");
const VfsInode = @import("../../fs/inode.zig");
const Errno = @import("../../errno.zig").Errno;
const File = @import("../../fs/file.zig");
const block_registry = @import("../../device/block/registry.zig");
const char_registry = @import("../../device/char/registry.zig");
const DeviceId = @import("../../device/types.zig").dev_t;
const memory = @import("../../memory.zig");

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

fn root_open(inode: *Inode, file: *File) Inode.Error.open!void {
    file.* = .{
        .inode = inode,
        .refs = 1,
        .vtable = &root_file_vtable,
    };
}

fn root_lookup(inode: *Inode, name: []const u8) Inode.Error.lookup!?*Inode {
    if (block_registry.get_partition_by_name(name)) |partition| {
        const ino: Superblock.Ino = .{
            .type = .Block,
            .device = partition.devt,
        };
        return inode.superblock.retrieve_inode(@bitCast(ino));
    } else if (char_registry.get_device_by_name(name)) |device| {
        const ino: Superblock.Ino = .{
            .type = .Character,
            .device = device.devt,
        };
        return inode.superblock.retrieve_inode(@bitCast(ino));
    } else {
        return null;
    }
}

const root_vtable: Inode.VTable = .{
    .open = &root_open,
    .lookup = &root_lookup,
    .link = &Inode.VTable.Generic.link,
    .unlink = &Inode.VTable.Generic.unlink,
};

pub fn root_preaddir(_: *File, pos: u64, dst: *File.DirEnt) File.Error.preaddir!usize {
    var current: usize = 0;
    var part_it = block_registry.partitions.inorderIterator(); // todo: This is not thread safe.
    while (part_it.next()) |node| {
        if (current == pos) {
            const ino: Superblock.Ino = .{
                .type = .Block,
                .device = node.key.devt,
            };
            const name_slice = std.mem.sliceTo(&node.key.name, 0);
            dst.* = .{
                .name = undefined,
                .name_len = name_slice.len,
                .type = .Block,
                .inode = @bitCast(ino),
            };
            @memcpy(dst.name[0..name_slice.len], name_slice);
            return 1;
        }
        current += 1;
    }
    var cdev_it = char_registry.devices.inorderIterator(); // todo: This is not thread safe.
    while (cdev_it.next()) |node| {
        if (current == pos) {
            const ino: Superblock.Ino = .{
                .type = .Character,
                .device = node.key.devt,
            };
            const name_slice = std.mem.sliceTo(&node.key.name, 0);
            dst.* = .{
                .name = undefined,
                .name_len = name_slice.len,
                .type = .Character,
                .inode = @bitCast(ino),
            };
            @memcpy(dst.name[0..name_slice.len], name_slice);
            return 1;
        }
        current += 1;
    }
    return 0;
}

const root_file_vtable: File.VTable = .{
    .preaddir = &root_preaddir,
    .readdir = &File.VTable.Generic.readdir,
    .seek = &File.VTable.Generic.seek,
    .close = &File.VTable.Generic.close,
};
