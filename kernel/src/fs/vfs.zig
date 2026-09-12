const std = @import("std");
const block = @import("../device/block/block.zig");
const registry = @import("../device/block/registry.zig");
const SuperBlock = @import("superblock.zig");
const FileSystem = @import("filesystem.zig");
const Inode = @import("inode.zig");
const Tnode = @import("tnode.zig");
const memory = @import("../memory.zig");
const Errno = @import("../errno.zig").Errno;
const scheduler = @import("../task/scheduler.zig");

const smallAlloc: std.mem.Allocator = @import("../memory.zig").smallAlloc.allocator();
const bigAlloc: std.mem.Allocator = @import("../memory.zig").bigAlloc.allocator();

var drivers: std.ArrayListUnmanaged(FileSystem) = .empty;

pub const PartIdentifier = union(enum) {
    UUID: []const u8,
    path: []const u8,
    virtual,
};

pub fn identify_fs(partition: *block.Partition) ?*FileSystem {
    for (drivers.items) |*fs| {
        if (fs.identify(partition)) {
            return fs;
        }
    } else return null;
}

pub fn has_uuid(partition: *block.Partition, uuid: u128) ?*FileSystem {
    for (drivers.items) |*fs| {
        if (fs.identify(partition) and fs.uuid(partition) == uuid) {
            return fs;
        }
    }
    return null;
}

pub fn scan_for_uuid(uuid: u128) ?struct { *FileSystem, *block.Partition } {
    var it = registry.partitions.inorderIterator();
    while (it.next()) |entry| {
        std.log.debug("{s}", .{entry.key.name});
        if (has_uuid(entry.key, uuid)) |fs| {
            std.log.debug("uuid match", .{});
            return .{ fs, entry.key };
        }
    }
    return null;
}

pub fn add_filesystem(fs: FileSystem) !void {
    try drivers.append(smallAlloc, fs);
}

fn get_fs_by_name(name: []const u8) ?*FileSystem {
    for (drivers.items) |*fs| {
        if (std.mem.eql(u8, name, fs.name)) {
            return fs;
        }
    }
    return null;
}

pub const MountOptions = struct {
    read_only: bool = false,
    fs: ?[]const u8 = null,
};

var root_dentry: ?Tnode = null;

pub fn create_hard_root(inode: *Inode) void {
    std.debug.assert(root_dentry == null);
    root_dentry = .{
        .name = "",
        .inode = inode,
        .parent = &(root_dentry.?),
        .refs = 1,
    };
}

pub fn get_hard_root() *Tnode {
    return &(root_dentry orelse @panic("no hard root"));
}

pub fn mount(dst: *Tnode, identifier: PartIdentifier, options: MountOptions) !void {
    var fs: ?*FileSystem = null;
    const partition: ?*block.Partition = switch (identifier) {
        .UUID => |uuid_str| b: {
            const uuid = @import("../misc/parse_uuid.zig").parse_uuid(uuid_str) orelse return Errno.ENOTBLK;
            fs, const part: *block.Partition = scan_for_uuid(uuid) orelse return Errno.ENOTBLK;
            break :b part;
        },
        .path => |path| b: {
            const tnode = try resolve(path);
            if (tnode.inode.mode.type != .Block) {
                return Errno.ENOTBLK;
            }
            const device = tnode.inode.type_specific.Block;
            break :b registry.get_partition(device) orelse return Errno.ENOTBLK;
        },
        .virtual => null,
    };
    if (options.fs) |fs_name| {
        fs = get_fs_by_name(fs_name) orelse return Errno.ENODEV;
    }
    const final_fs = fs orelse (if (partition) |p| identify_fs(p) else null) orelse return Errno.ENODEV;
    const superblock = final_fs.create(partition, memory.smallAlloc.allocator());
    try dst.mount(try superblock.get_root());
}

pub fn init() !void {
    try Tnode.init_cache();
    try Inode.init_cache();
    try @import("file.zig").init_cache();
}

fn resolve_max_symlink(cwd: *Tnode, path: []const u8, max_symlink: usize) !*Tnode {
    var it = std.fs.path.componentIterator(path) catch unreachable;
    var current_dentry = (if (it.root() == null) cwd else scheduler.get_current_task().root).get_ref();
    errdefer current_dentry.release();
    while (it.next()) |component| {
        const next = current_dentry.lookup(component.name) orelse return Errno.ENOENT;
        errdefer next.release();
        if (it.peekNext() != null and next.inode.mode.type == .Link) {
            if (max_symlink == 0) {
                return Errno.ELOOP;
            }
            const resolved_link = try resolve_max_symlink(current_dentry, next.inode.type_specific.Link, max_symlink - 1);
            current_dentry.release();
            next.release();
            current_dentry = resolved_link;
        } else {
            current_dentry.release();
            current_dentry = next;
        }
    }
    return current_dentry;
}

pub fn resolve_at(cwd: *Tnode, path: []const u8) !*Tnode {
    return resolve_max_symlink(cwd, path, 5); // todo: remove magic number
}

pub fn resolve(path: []const u8) !*Tnode {
    return resolve_at(scheduler.get_current_task().cwd, path);
}
