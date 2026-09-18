const std = @import("std");
pub const Id = 57;
const Errno = @import("../errno.zig").Errno;
const vfs = @import("../fs/vfs.zig");
const Inode = @import("../fs/inode.zig");
const Superblock = @import("../fs/superblock.zig");
const Off = @import("../fs/file.zig").Off;
const scheduler = @import("../task/scheduler.zig");
const dev_t = @import("../device//types.zig").dev_t;

pub const TimeSpec = extern struct {
    sec : usize, // todo: time_t
    nsecs : isize,
};

pub const Stat = extern struct {
    dev : dev_t,             // Device ID of device containing file.
    ino : Inode.Ino,             // File serial number.
    mode : Inode.Mode,           // Mode of file (see below).
    nlink : usize, // nlink_t,         // Number of hard links to the file.
    uid : usize, // uid_t,             // User ID of file.
    gid : usize, // gid_t,             // Group ID of file.
    rdev : dev_t,
    size : u64, // off_t,            // For regular files, the file size in bytes.
    atim : TimeSpec,  // Last data access timestamp.
    mtim : TimeSpec,  // Last data modification timestamp.
    ctim : TimeSpec,  // Last file status change timestamp.
    blksize : Superblock.BlockSize,
    blocks : Superblock.BlockCount,
};

// todo: should be Off
pub fn do(path: [*:0]const u8, dst : *Stat) !void {
    const tnode = try vfs.resolve_final(std.mem.span(path));
    defer tnode.release();
    const inode = tnode.inode;
    dst.* = .{
        .dev = inode.superblock.partition.devt,
        .gid = inode.gid,
        .ino = inode.ino,
        .uid = inode.uid,
        .mode = inode.mode,
        .nlink = inode.hard_links,
        .size = inode.size,
        .atim = undefined,
        .mtim = undefined,
        .ctim = undefined,
        .blksize = inode.superblock.block_size,
        .blocks = inode.blocks,
        .rdev = switch (inode.type_specific) {
            .Block => |dev| dev,
            .Character => |dev| dev,
            else => undefined,
        }
    };
}
