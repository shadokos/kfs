const std = @import("std");
pub const Id = 18;
const Errno = @import("../errno.zig").Errno;
const vfs = @import("../fs/vfs.zig");
const TNode = @import("../fs/tnode.zig");
const INode = @import("../fs/inode.zig");
const scheduler = @import("../task/scheduler.zig");
const TaskDescriptor = @import("../task/task.zig").TaskDescriptor;

pub const Flags = packed struct(u32) {
    openMode: OpenMode,
    append: bool = false,
    close_on_exec: bool = false,
    close_on_fork: bool = false,
    create: bool = false,
    directory: bool = false,
    exclusive: bool = false,
    no_controlling_tty: bool = false,
    no_follow: bool = false,
    non_blocking: bool = false,
    truncate: bool = false,
    tty_init: bool = false,
    _: u18 = 0,

    pub const OpenMode = enum(u3) {
        exec,
        read_only,
        read_write,
        search,
        wronly,
    };
};

pub const Mode = packed struct(u32) {
    suid: bool = false,
    sgid: bool = false,
    svtx: bool = false,
    other: Perm = .{},
    group: Perm = .{},
    user: Perm = .{},
    _: u20 = 0,

    pub const Perm = packed struct {
        Execute: bool = false,
        Write: bool = false,
        Read: bool = false,
        pub fn to_vfs(self: @This()) INode.Mode.Perm {
            return .{
                .execute = self.Execute,
                .read = self.Read,
                .write = self.Write,
            };
        }
    };

    pub fn to_vfs(self: @This(), ty: INode.Mode.Type) INode.Mode {
        return .{
            .group = self.group.to_vfs(),
            .other = self.other.to_vfs(),
            .owner = self.user.to_vfs(),
            .suid = self.suid,
            .sgid = self.sgid,
            .restricted_deletion = self.svtx,
            .type = ty,
        };
    }
};

fn create_file(path_slice: []const u8, flags: Flags, mode: Mode) Errno!*TNode {
    const dir_path = std.fs.path.dirnamePosix(path_slice) orelse if (std.fs.path.isAbsolutePosix(path_slice)) "/" else ".";
    const name = std.fs.path.basenamePosix(path_slice);
    const dir_tnode = try vfs.resolve(dir_path);
    defer dir_tnode.release();

    // todo: lock dir_tnode.inode to ensure atomicity

    if (dir_tnode.lookup(name)) |existing| {
        errdefer existing.release();
        return if (flags.exclusive) Errno.EEXIST else existing;
    }

    const inode = try dir_tnode.inode.superblock.create_inode(0, 0, mode.to_vfs(.Regular), .{ .Regular = {} });
    defer inode.release();

    try dir_tnode.inode.link(name, inode);
    return dir_tnode.lookup(name) orelse unreachable;
}

pub fn do(path: [*:0]const u8, flags: Flags, mode: Mode) Errno!TaskDescriptor.Fd {
    const tnode = if (flags.create) try create_file(std.mem.span(path), flags, mode) else try vfs.resolve(std.mem.span(path));
    defer tnode.release();
    const inode = tnode.inode;
    if (flags.truncate) {
        try inode.truncate(0);
    }
    if (flags.append or
        flags.close_on_exec or
        flags.close_on_fork or
        flags.directory or
        flags.no_controlling_tty or
        flags.no_follow or
        flags.non_blocking or
        flags.tty_init)
    {
        @panic("not implemented");
    }
    const file = try tnode.inode.open();
    errdefer file.close() catch {};
    return scheduler.get_current_task().add_file(file) orelse return Errno.EMFILE;
}
