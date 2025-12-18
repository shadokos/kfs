const std = @import("std");
const VfsInode = @import("../inode.zig");

pub const Ino = u32;
pub const BlockAddress = u32;
pub const RootDir: Ino = 2;

pub const Superblock = packed struct(u8192) {
    inodes: u32,
    blocks: u32,
    reserved_blocks: u32,
    unallocated_blocks: u32,
    unallocated_inodes: u32,
    superblock: u32,
    block_size_log: u32,
    fragment_size_log: u32,
    block_per_group: u32,
    fragment_per_group: u32,
    inode_per_group: u32,
    last_mount_time: u32,
    last_written_time: u32,
    mounts_since_last_check: u16,
    mounts_before_check: u16,
    signature: u16,
    state: State,
    error_handling: ErrorHandling,
    version_minor: u16,
    last_check_time: u32,
    check_interval: u32,
    os_id: u32,
    version_major: u32,
    uid: u16,
    gid: u16,
    extended: ExtendedSuperblock,
    _unused2: std.meta.Int(.unsigned, 8 * (1024 - 236)),

    pub const State = enum(u16) {
        clean = 1,
        errors = 2,
    };

    pub const ErrorHandling = enum(u16) {
        ignore = 1,
        remount_ro = 2,
        panic = 3,
    };

    pub const OSId = enum(u32) {
        linux = 0,
        hurd = 1,
        masix = 2,
        freebsd = 3,
        other = 4,
    };
};

pub const ExtendedSuperblock = packed struct(u1216) {
    first_inode: u32,
    inode_size: u16,
    block_group: u16,
    optional_features: OptionalFeature,
    required_features: RequiredFeature,
    read_only_features: ReadOnlyFeature,
    uuid: u128,
    // volume_name: [16:0]u8,
    volume_name: u128,
    // last_mount_path_volume: [64:0]u8,
    last_mount_path_volume: u512,
    compression_algorithm: u32,
    file_preallocate: u8,
    dir_preallocate: u8,
    _unused: u16,
    journal_id: u128,
    journal_inode: u32,
    journal_device: u32,
    orphans_head: u32,

    pub const OptionalFeature = packed struct(u32) {
        preallocate_dir: bool,
        afs_server: bool,
        ext3_journal: bool,
        extended_attributes: bool,
        autoresize: bool,
        hash_index_dir: bool,
        _unused: u26,
    };

    pub const RequiredFeature = packed struct(u32) {
        compression: bool,
        dir_type: bool,
        replay_journal: bool,
        journal: bool,
        _unused: u28,
    };

    pub const ReadOnlyFeature = packed struct(u32) {
        sparse_superblock: bool,
        fs_64: bool,
        binary_tree: bool,
        _unused: u29,
    };
};

pub const BlockGroupDescriptor = packed struct(u256) {
    block_bitmap_address: BlockAddress,
    inode_bitmap_address: BlockAddress,
    inode_table_start: BlockAddress,
    free_blocks: u16,
    free_inodes: u16,
    directories: u16,
    _unused: u112,
};

pub const Inode = extern struct {
    mode: Mode align(1),
    uid: u16 align(1),
    lower_size: u32 align(1),
    last_access_time: u32 align(1),
    creation_time: u32 align(1),
    last_modification_time: u32 align(1),
    deletion_time: u32 align(1),
    gid: u16 align(1),
    hard_links: u16 align(1),
    sectors: u32 align(1),
    flags: Flags align(1),
    OS_val1: u32 align(1),
    direct_block_pointer: [12]u32 align(1),
    singly_indirect_pointer: u32 align(1),
    doubly_indirect_pointer: u32 align(1),
    triply_indirect_pointer: u32 align(1),
    generation: u32 align(1),
    acl_block: u32 align(1),
    upper_file_size: u32 align(1),
    fragment_address: u32 align(1),
    OS_val2: OSVal2 align(1),

    pub const Mode = packed struct(u16) {
        permission: Permission,
        type: Type,

        pub fn from_vfs(vfs: VfsInode.Mode) ?@This() {
            return .{
                .type = Type.from_vfs(vfs.type) orelse return null,
                .permission = .{
                    .other = Permission.EWR.from_vfs(vfs.other),
                    .group = Permission.EWR.from_vfs(vfs.group),
                    .user = Permission.EWR.from_vfs(vfs.owner),
                    .suid = vfs.suid,
                    .sgid = vfs.sgid,
                    .sticky_bit = vfs.restricted_deletion,
                },
            };
        }

        pub fn to_vfs(self: @This()) ?VfsInode.Mode {
            return VfsInode.Mode{
                .type = self.type.to_vfs() orelse return null,
                .other = self.permission.other.to_vfs(),
                .group = self.permission.group.to_vfs(),
                .owner = self.permission.user.to_vfs(),
                .suid = self.permission.suid,
                .sgid = self.permission.sgid,
                .restricted_deletion = self.permission.sticky_bit,
            };
        }
    };

    pub const Type = enum(u4) {
        invalid = 0,
        fifo = 0x1,
        character_device = 0x2,
        directory = 0x4,
        block_device = 0x6,
        regular_file = 0x8,
        symbolic_link = 0xa,
        unix_socket = 0xc,

        pub fn from_vfs(vfs: VfsInode.Mode.Type) ?@This() {
            return switch (vfs) {
                .Block => .block_device,
                .Character => .character_device,
                .Directory => .directory,
                .Fifo => .fifo,
                .Regular => .regular_file,
                .Link => .symbolic_link,
                .Socket => .unix_socket,
            };
        }

        pub fn to_vfs(self: @This()) ?VfsInode.Mode.Type {
            return switch (self) {
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
    };

    pub const Permission = packed struct(u12) {
        other: EWR,
        group: EWR,
        user: EWR,
        sticky_bit: bool,
        sgid: bool,
        suid: bool,

        pub const EWR = packed struct(u3) {
            execute: bool,
            write: bool,
            read: bool,

            pub fn from_vfs(vfs: VfsInode.Mode.Perm) @This() {
                return .{
                    .execute = vfs.execute,
                    .write = vfs.write,
                    .read = vfs.read,
                };
            }

            pub fn to_vfs(self: @This()) VfsInode.Mode.Perm {
                return .{
                    .execute = self.execute,
                    .write = self.write,
                    .read = self.read,
                };
            }
        };
    };

    pub const Flags = packed struct(u32) {
        secure_deletion: bool,
        copy_on_delete: bool,
        compression: bool,
        synchronous_update: bool,
        immutable: bool,
        append_only: bool,
        no_dump: bool,
        freeze_last_access: bool,
        _reserved: u8,
        hash_indexed_dir: bool,
        afs_dir: bool,
        journal_file_data: bool,
        _unused: u13,
    };

    pub const OSVal2 = extern union {
        linux: extern struct {
            fragment: u8 align(1),
            fragment_size: u8 align(1),
            _reserved: u16 align(1),
            high_uid: u16 align(1),
            high_gid: u16 align(1),
            _reserved2: u32 align(1),
        } align(1),
        hurd: extern struct {
            fragment: u8 align(1),
            fragment_size: u8 align(1),
            high_type_perm: u16 align(1),
            high_uid: u16 align(1),
            high_gid: u16 align(1),
            author_uid: u32 align(1),
        } align(1),
        masix: extern struct {
            fragment: u8 align(1),
            fragment_size: u8 align(1),
        } align(1),
    };

    const Self = @This();

    pub fn get_size(self: Self) u64 {
        return (@as(u64, self.upper_file_size) << 32) | self.lower_size;
    }

    pub fn set_size(self: *Self, size: u64) void {
        self.lower_size = @truncate(size);
        self.upper_file_size = @truncate(size >> 32);
    }
};

pub const DirectoryEntry = extern struct {
    inode: Ino align(1),
    size: u16 align(1),
    name_length: u8 align(1),
    type: Type align(1),
    name: [0]u8 align(1),

    pub const Type = enum(u8) {
        unknown = 0,
        regular_file = 1,
        directory = 2,
        character_device = 3,
        block_device = 4,
        fifo = 5,
        socket = 6,
        symbolic_link = 7,
    };
};

comptime {
    std.debug.assert(@sizeOf(DirectoryEntry) == 8);
}

pub fn dir_ent_type_to_inode_type(t: DirectoryEntry.Type) Inode.Type {
    return switch (t) {
        .unknown => .invalid,
        .regular_file => .regular_file,
        .directory => .directory,
        .character_device => .character_device,
        .block_device => .block_device,
        .fifo => .fifo,
        .socket => .unix_socket,
        .symbolic_link => .symbolic_link,
    };
}

pub fn inode_type_to_dir_ent_type(t: Inode.Type) DirectoryEntry.Type {
    return switch (t) {
        .invalid => .unknown,
        .regular_file => .regular_file,
        .directory => .directory,
        .character_device => .character_device,
        .block_device => .block_device,
        .fifo => .fifo,
        .unix_socket => .socket,
        .symbolic_link => .symbolic_link,
    };
}
