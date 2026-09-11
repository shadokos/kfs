const Ext2Superblock = @import("superblock.zig");
const Ext2Inode = @import("inode.zig");
const Ext2 = @import("ext2.zig");
const Superblock = @import("../../fs/superblock.zig");
const Inode = @import("../../fs/inode.zig");
const File = @import("../../fs/file.zig");

fn convert_inode_type(t: Ext2.Inode.Type) ?Inode.Mode.Type {
    return switch (t) {
        .block_device => .Block,
        .character_device => .Character,
        .directory => .Directory,
        .fifo => .Fifo,
        .invalid => null,
        .regular_file => .Regular,
        .symbolic_link => .Link,
        .unix_socket => .Socket,
    };
}

fn convert_dirent_type(t: Ext2.DirectoryEntry.Type) ?Inode.Mode.Type {
    return switch (t) {
        .unknown => null,
        .block_device => .Block,
        .character_device => .Character,
        .directory => .Directory,
        .fifo => .Fifo,
        .regular_file => .Regular,
        .symbolic_link => .Link,
        .socket => .Socket,
    };
}

fn convert_dirent(ext2: Ext2Inode.DirEnt) File.DirEnt {
    return .{
        .inode = ext2.ino,
        .name = ext2.name,
        .name_len = ext2.name_len,
        .type = (convert_dirent_type(ext2.type)) orelse @panic("todo: handle invalid type"),
    };
}

pub const file_vtable: File.VTable = .{
    .flush = &vtable_flush,
    .pread = &vtable_read_data,
    .pwrite = &vtable_write_data,
    .preaddir = &vtable_preaddir,
    .write = File.VTable.Generic.write,
    .read = File.VTable.Generic.read,
    .seek = File.VTable.Generic.seek,
    .readdir = File.VTable.Generic.readdir,
    .close = File.VTable.Generic.close,
};

pub fn vtable_flush(base: *File) File.Error.flush!void {
    return Ext2Inode.FromVfs(base.inode).flush();
}

pub fn vtable_read_data(base: *File, pos: u64, buffer: []u8) File.Error.pread!usize {
    return Ext2Inode.FromVfs(base.inode).pread(pos, buffer);
}

pub fn vtable_preaddir(base: *File, pos: u64, dst: *Inode.DirEnt) File.Error.preaddir!usize {
    var name_slice: []u8 = dst.name[0..];
    const tmp = (try Ext2Inode.FromVfs(base.inode).read_directory_entry(pos, &name_slice)) orelse return 0;
    dst.inode = tmp.inode;
    dst.name_len = @intCast(name_slice.len);
    dst.type = convert_dirent_type(tmp.type) orelse @panic("todo");
    return tmp.size;
}

pub fn vtable_write_data(base: *File, pos: u64, buffer: []const u8) File.Error.pwrite!usize {
    return Ext2Inode.FromVfs(base.inode).pwrite(pos, buffer);
}

pub fn vtable_lookup(base: *Inode, name: []const u8) Inode.Error.lookup!?*Inode {
    return (try Ext2Inode.FromVfs(base).lookup(name) orelse return null).ToVfs();
}

pub fn vtable_link(base: *Inode, name: []const u8, other: *Inode) Inode.Error.link!void {
    return Ext2Inode.FromVfs(base).add_entry(name, Ext2Inode.FromVfs(other));
}

pub fn vtable_unlink(base: *Inode, name: []const u8) Inode.Error.unlink!void {
    if (!try Ext2Inode.FromVfs(base).remove_entry(name))
        return error.ENOENT;
}

pub fn vtable_truncate(base: *Inode, new_size: u64) Inode.Error.truncate!void {
    return Ext2Inode.FromVfs(base).truncate(new_size);
}

pub fn vtable_open(base: *Inode, file: *File) Inode.Error.open!void {
    file.* = .{
        .inode = base.get_ref(),
        .pos = 0,
        .vtable = &file_vtable,
        .refs = 1,
    };
}

pub const inode_vtable: Inode.VTable = .{
    .open = &vtable_open,
    .link = &vtable_link,
    .unlink = &vtable_unlink,
    .lookup = &vtable_lookup,
    .truncate = &vtable_truncate,
};

pub fn vtable_get_root(superblock: *Superblock) Superblock.Error.get_root!*Inode {
    return (try Ext2Superblock.FromVfs(superblock).get_root()).ToVfs();
}

pub fn create_inode(
    superblock: *Superblock,
    uid: Inode.Uid,
    gid: Inode.Gid,
    mode: Inode.Mode,
    type_specific: Superblock.TypeSpecificParams,
) Superblock.Error.create_inode!*Inode {
    return (try Ext2Superblock.FromVfs(superblock).create_inode(uid, gid, mode, type_specific)).ToVfs();
}

pub fn vtable_load_inode(superblock: *Superblock, ino: Inode.Ino) Superblock.Error.load_inode!*Inode {
    return (try Ext2Superblock.FromVfs(superblock).load_inode(ino)).ToVfs();
}

pub fn vtable_release_inode(superblock: *Superblock, inode: *Inode) Superblock.Error.release_inode!void {
    return Ext2Superblock.FromVfs(superblock).release_inode(Ext2Inode.FromVfs(inode));
}

pub const superblock_vtable: Superblock.VTable = .{
    .load_inode = &vtable_load_inode,
    .release_inode = &vtable_release_inode,
    .get_root = &vtable_get_root,
    .create_inode = &create_inode,
};

pub fn getSuperblock(ext2: *Ext2Superblock) *Superblock {
    return ext2.ToVfs();
}
