const std = @import("std");

pub const Superblock = packed struct(std.meta.Int(.unsigned, 8 * 84)) {
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

pub const ExtendedSuperblock = packed struct(std.meta.Int(.unsigned, 8 * (1024 - 84))) {
    first_inode: u32,
    inode_size: u16,
    block_group: u16,
    optional_features: u32,
    required_features: u32,
    read_only_features: u32,
    fs_id: u128,
    volume_name: [16:0]u8,
    last_mount_path_volume: [64:0]u8,
    compression_algorithm: u32,
    file_preallocate: u8,
    dir_preallocate: u8,
    _unused: u16,
    journal_id: u128,
    journal_inode: u32,
    journal_device: u32,
    orphans_head: u32,
    _unused2: std.meta.Int(.unsigned, 8 * (1024 - 236)),

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
        _unused: u28,
    };
};

pub const BlockGroupDescriptor = packed struct(u256) {
    block_bitmap_address: u32,
    inode_bitmap_address: u32,
    inode_table_start: u32,
    free_blocks: u16,
    free_inodes: u16,
    directories: u16,
};

pub const Inode = packed struct(u512) {
    type: Type,
    permission: Permission,
    uid: u16,
    lower_size: u32,
    last_access_time: u32,
    creation_time: u32,
    last_modification_time: u32,
    deletion_time: u32,
    gid: u16,
    hard_links: u16,
    sectors: u32,
    flags: Flags,
    OS_val1: u32,
    direct_block_pointer: [12]u32,
    singly_indirect_pointer: u32,
    doubly_indirect_pointer: u32,
    triply_indirect_pointer: u32,
    generation: u32,
    acl_block: u32,
    upper_file_size: u32,
    fragment_address: u32,
    OS_val2: OSVal2,

    pub const Type = enum(u4) {
        fifo = 0x1,
        character_device = 0x2,
        directory = 0x4,
        block_device = 0x6,
        regular_file = 0x8,
        symbolic_link = 0xa,
        unix_socket = 0xc,
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

    pub const OSVal2 = packed union {
        linux: packed struct(u96) {
            fragment: u8,
            fragment_size: u8,
            _reserved: u16,
            high_uid: u16,
            high_gid: u16,
            _reserved2: u32,
        },
        hurd: packed struct(u96) {
            fragment: u8,
            fragment_size: u8,
            high_type_perm: u16,
            high_uid: u16,
            high_gid: u16,
            author_uid: u32,
        },
        masix: packed struct(u96) {
            fragment: u8,
            fragment_size: u8,
            _reserved: u80,
        },
    };
};

pub const DirectoryEntry = packed struct(u64) {
    inode: u32,
    size: u16,
    name_length: u16, // high byte can be type indicator
    name: [0]u8,

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
