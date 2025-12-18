const std = @import("std");
const ext2 = @import("ext2.zig");
const Inode = @import("inode.zig");
const Partition = @import("../../device/block/partition.zig");
const blk = @import("../../device/block/block.zig");
const BitSet = @import("bit_set.zig");
const VfsSuperblock = @import("../superblock.zig");
const VfsInode = @import("../inode.zig");
const Errno = @import("../../errno.zig").Errno;

const logger = std.log.scoped(.ext2_superblock);

allocator: std.mem.Allocator, //todo: remove
extended: bool,
inode_size: usize,
inode_per_group: usize,
block_per_group: usize,
vfs: VfsSuperblock,

pub const WriteError = error{
    EIO,
    ENODEV,
    EBUSY,
    EPERM,
    ENOMEM,
};

pub const ReadError = error{
    EIO,
    ENODEV,
    EBUSY,
    EPERM,
    ENOMEM,
};

pub const AllocationError = error{ ENOMEM, ENOSPC } || WriteError || ReadError;

const Self = @This();

pub fn init(
    partition: *Partition,
    allocator: std.mem.Allocator,
    read_only: bool,
) ReadError!Self {
    var tmp_sb: Self = undefined;
    tmp_sb.allocator = allocator;
    tmp_sb.vfs.block_size = 1024;
    tmp_sb.vfs.partition = partition;

    const sb = try tmp_sb.read_something(ext2.Superblock, 1, 0);

    // if (!can_be_mounted(sb)) {
    //     @panic("todo, fs contains unsupported features");
    // }

    var actual_read_only = read_only;
    if (!read_only and should_be_readonly(sb)) {
        actual_read_only = true;
        logger.info("filesystem mounted as read only because it contains readonly features", .{});
    }

    const extended = sb.version_major >= 1;
    const block_size = @as(usize, 1) << @as(u5, @intCast(10 + sb.block_size_log));

    return Self{
        .allocator = allocator,
        .extended = extended,
        .inode_size = if (extended) sb.extended.inode_size else 128,
        .inode_per_group = sb.inode_per_group,
        .block_per_group = sb.block_per_group,
        .vfs = .{
            .block_size = block_size,
            .fragment_size = block_size,
            .blocks = sb.blocks,
            .free_blocks = sb.unallocated_blocks,
            .reserved_blocks = sb.reserved_blocks,
            .files = sb.inodes,
            .free_files = sb.unallocated_inodes,
            .reserved_files = 0,
            .fsid = if (extended) @truncate(sb.extended.uuid ^ (sb.extended.uuid >> 64)) else null,
            .max_name = 256, // todo: deduplicate
            .flags = .{
                .read_only = actual_read_only,
                .no_suid = false,
            },
            .uuid = if (extended) sb.extended.uuid else null,
            .partition = partition,
            .vtable = &@import("interface.zig").superblock_vtable,
            .cache = VfsSuperblock.InodeCache.init(allocator),
        },
    };
}

fn can_be_mounted(superblock: ext2.Superblock) bool {
    if (superblock.block_size_log != superblock.fragment_size_log) {
        return false; // We don't support fragments
    }

    if (superblock.version_major >= 1) {
        const extended = superblock.extended;

        // We don't support inode_size different from 128
        if (extended.inode_size != @sizeOf(ext2.Inode)) {
            return false;
        }

        // We don't support any of those features.
        if (extended.required_features.compression or
            extended.required_features.dir_type or
            extended.required_features.journal or
            extended.required_features.replay_journal)
        {
            return false;
        }
    }
    return true;
}

fn should_be_readonly(superblock: ext2.Superblock) bool {
    if (superblock.version_major >= 1) {
        const extended = superblock.extended;
        if (extended.read_only_features.binary_tree or
            extended.read_only_features.sparse_superblock)
        {
            return false;
        }
    }
    return false;
}

pub fn FromVfs(vfs: *VfsSuperblock) *Self {
    return @fieldParentPtr("vfs", vfs);
}

pub fn ToVfs(self: *Self) *VfsSuperblock {
    return &self.vfs;
}

pub fn load_inode(self: *Self, ino: @import("../inode.zig").Ino) (error{ENOMEM} || ReadError)!*Inode {
    const inode = try Inode.create();
    try inode.init_and_fetch(self, ino);
    return inode;
}

pub fn retrieve_inode(self: *Self, ino: @import("../inode.zig").Ino) VfsSuperblock.Error.load_inode!*Inode {
    return Inode.FromVfs(try self.ToVfs().retrieve_inode(ino));
}

pub fn release_inode(self: *Self, inode: *Inode) void {
    std.log.debug("ext2.superblock.release_inode: hard_links: {}", .{inode.vfs.hard_links});
    if (inode.vfs.hard_links == 0) {
        self.destroy_inode(inode) catch @panic("todo");
    } else {
        inode.flush() catch @panic("todo");
    }
    Inode.destroy(inode);
}

pub fn fetch(self: *Self) ReadError!void {
    const ext2_sb = try self.readSuperBlock(self.vfs.ino);

    self.vfs.block_size = @as(usize, 1) << @as(u5, @intCast(10 + ext2_sb.block_size_log));

    if (ext2_sb.version_major >= 1) {
        self.extended = true;
        self.inode_size = ext2_sb.extended.inode_size;
    }
}

pub fn flush(self: *Self) WriteError!void {
    var ext2_superblock = try self.readSuperBlock();
    ext2_superblock.unallocated_blocks = self.vfs.free_blocks;
    ext2_superblock.unallocated_inodes = self.vfs.free_files;
    try self.write_something(ext2_superblock, 1, 0);
}

pub fn write_block(self: *Self, block: usize, buffer: []const u8) WriteError!void {
    return self.vfs.partition.write(
        block * (self.vfs.block_size / blk.STANDARD_BLOCK_SIZE),
        self.vfs.block_size / blk.STANDARD_BLOCK_SIZE,
        buffer[0..],
    ) catch |e| {
        std.log.warn("in write_block: {s}", .{@errorName(e)});
        return switch (e) {
            error.DeviceNotFound => WriteError.ENODEV,
            error.WriteProtected => WriteError.EPERM,
            error.OutOfMemory => WriteError.ENOMEM,
            error.DeviceBusy => WriteError.EBUSY,
            error.AlreadyExists, error.BufferTooSmall, error.OutOfBounds, error.NotSupported, error.IoError, error.NoFreeBuffers, error.InvalidOperation, error.MediaNotPresent, error.CorruptedData => WriteError.EIO,
        };
    };
}

pub fn write_bytes(self: *Self, src: []const u8, block: usize, offset: usize) WriteError!void {
    var block_buffer: []u8 = self.allocator.alloc(u8, self.vfs.block_size) catch @panic("todo");
    defer self.allocator.free(block_buffer);
    var current_block = block;
    var src_pos: usize = 0;
    var file_offset = offset;
    while (src_pos < src.len) {
        try self.read_block(current_block, block_buffer);
        const partial_begin: usize = file_offset % self.vfs.block_size;
        const partial_end: usize = @min(self.vfs.block_size, partial_begin + src.len - src_pos);

        @memcpy(block_buffer[partial_begin..partial_end], src[src_pos..][0 .. partial_end - partial_begin]);
        try self.write_block(current_block, block_buffer); // todo: return partial in case of error

        src_pos += partial_end - partial_begin;
        file_offset += partial_end - partial_begin;
        current_block += 1;
    }
}

pub fn write_something(self: *Self, data: anytype, block: usize, offset: usize) WriteError!void {
    try self.write_bytes(std.mem.asBytes(&data), block, offset);
}

pub fn read_block(self: *Self, block: usize, buffer: []u8) ReadError!void {
    return self.vfs.partition.read(
        block * (self.vfs.block_size / blk.STANDARD_BLOCK_SIZE),
        self.vfs.block_size / blk.STANDARD_BLOCK_SIZE,
        buffer[0..],
    ) catch |e| switch (e) {
        error.DeviceNotFound => ReadError.ENODEV,
        error.WriteProtected => ReadError.EPERM,
        error.OutOfMemory => ReadError.ENOMEM,
        error.DeviceBusy => ReadError.EBUSY,
        error.AlreadyExists, error.BufferTooSmall, error.OutOfBounds, error.NotSupported, error.IoError, error.NoFreeBuffers, error.InvalidOperation, error.MediaNotPresent, error.CorruptedData => ReadError.EIO,
    };
}

pub fn read_bytes(self: *Self, dst: []u8, block: usize, offset: usize) ReadError!void {
    var block_buffer: []u8 = self.allocator.alloc(u8, self.vfs.block_size) catch @panic("todo");
    defer self.allocator.free(block_buffer);
    var current_block = block;
    var dst_pos: usize = 0;
    var file_offset = offset;
    while (dst_pos < dst.len) {
        try self.read_block(current_block, block_buffer);
        const partial_begin: usize = file_offset % self.vfs.block_size;
        const partial_end: usize = @min(self.vfs.block_size, partial_begin + dst.len - dst_pos);
        @memcpy(dst[dst_pos..][0 .. partial_end - partial_begin], block_buffer[partial_begin..partial_end]);
        dst_pos += partial_end - partial_begin;
        file_offset += partial_end - partial_begin;
        current_block += 1;
    }
}

pub fn read_something(self: *Self, comptime T: type, block: usize, offset: usize) ReadError!T {
    var ret: T = undefined;
    try self.read_bytes(std.mem.asBytes(&ret), block, offset);

    return ret;
}

pub fn readSuperBlock(self: *Self) ReadError!ext2.Superblock {
    return if (self.vfs.block_size == 1024)
        self.read_something(ext2.Superblock, 1, 0)
    else
        self.read_something(ext2.Superblock, 0, 1024);
}

pub fn readBlockGroupDescriptor(self: *Self, group: usize) ReadError!ext2.BlockGroupDescriptor {
    const begin: ext2.BlockAddress = if (self.vfs.block_size == 1024) 2 else 1;
    const bgd_per_block = self.vfs.block_size / @sizeOf(ext2.BlockGroupDescriptor);
    const block = group / bgd_per_block;
    const index = group % bgd_per_block;
    return self.read_something(ext2.BlockGroupDescriptor, begin + block, index * @sizeOf(ext2.BlockGroupDescriptor));
}

pub fn writeBlockGroupDescriptor(self: *Self, group: usize, bgd: ext2.BlockGroupDescriptor) WriteError!void {
    const begin: ext2.BlockAddress = if (self.vfs.block_size == 1024) 2 else 1;
    const bgd_per_block = self.vfs.block_size / @sizeOf(ext2.BlockGroupDescriptor);
    const block = group / bgd_per_block;
    const index = group % bgd_per_block;
    return self.write_something(bgd, begin + block, index * @sizeOf(ext2.BlockGroupDescriptor));
}

pub fn readInode(self: *Self, ino: ext2.Ino) ReadError!ext2.Inode {
    const block_address, const index_in_block = try self.get_inode_address(ino);
    return self.read_something(ext2.Inode, block_address, index_in_block * self.inode_size);
}

pub fn writeInode(self: *Self, ino: ext2.Ino, inode: ext2.Inode) WriteError!void {
    const block_address, const index_in_block = try self.get_inode_address(ino);
    return self.write_something(inode, block_address, index_in_block * self.inode_size);
}

pub fn get_inode_address(self: *Self, ino: ext2.Ino) ReadError!struct { ext2.BlockAddress, usize } {
    const group = (ino - 1) / self.inode_per_group;
    const index = (ino - 1) % self.inode_per_group;

    const bgd: ext2.BlockGroupDescriptor = self.readBlockGroupDescriptor(group) catch unreachable;
    const inode_per_block = self.vfs.block_size / self.inode_size;
    const block_in_group = index / inode_per_block;
    const index_in_block = index % inode_per_block;
    return .{ bgd.inode_table_start + block_in_group, index_in_block };
}

pub fn create_inode(
    self: *Self,
    uid: VfsInode.Uid,
    gid: VfsInode.Gid,
    mode: VfsInode.Mode,
    type_specific: VfsSuperblock.TypeSpecificParams,
) (WriteError || AllocationError)!*Inode {
    const ret = try Inode.create();
    errdefer Inode.destroy(ret);

    const ino = try self.alloc_inode(0);
    errdefer self.free_ino(ino) catch @panic("todo");

    try ret.init_create(.{
        .superblock = self.ToVfs(),
        .ino = ino,
        .hard_links = 0,
        .size = 0,
        .uid = uid,
        .gid = gid,
        .mode = mode,
        .type_specific = undefined,
        .vtable = &@import("interface.zig").inode_vtable,
    }, type_specific);
    return ret;
}

pub fn destroy_inode(self: *Self, inode: *Inode) !void {
    try inode.truncate(0);
    try self.free_ino(inode.vfs.ino);
}

pub fn alloc_block(self: *Self, first_ino: ext2.Ino) AllocationError!ext2.BlockAddress {
    const bitmap_buffer = self.allocator.alloc(u8, self.vfs.block_size) catch return AllocationError.ENOMEM;
    defer self.allocator.free(bitmap_buffer);

    const bitmap = BitSet{ .buffer = bitmap_buffer };

    const total_groups = self.vfs.blocks / self.block_per_group;
    const inode_group = first_ino / self.inode_per_group;

    //todo: check caller uid somewhere

    for (0..total_groups) |i| {
        const group = (inode_group + i) % total_groups;

        var descriptor = try self.readBlockGroupDescriptor(group);

        if (descriptor.free_blocks == 0) continue;

        try self.read_block(descriptor.block_bitmap_address, bitmap_buffer);

        if (bitmap.toggle_first_unset()) |bit| {
            const block: ext2.BlockAddress = group * self.block_per_group + bit;
            if (block >= self.vfs.blocks) continue; // last block group might be incomplete and bit states after max block are undefined.

            // Zero init the block
            const buffer = self.allocator.alloc(u8, self.vfs.block_size) catch return AllocationError.ENOMEM;
            defer self.allocator.free(buffer);
            @memset(buffer, 0);
            try self.write_block(block, buffer);

            try self.write_block(descriptor.block_bitmap_address, bitmap_buffer);
            descriptor.free_blocks -= 1;
            try self.writeBlockGroupDescriptor(group, descriptor);

            self.vfs.free_blocks -= 1;
            return block;
        } else @panic("ill formed block bitmap"); // todo: fs shouldn't panic.
    }
    return error.ENOSPC;
}

pub fn alloc_inode(self: *Self, first_ino: ext2.Ino) AllocationError!ext2.Ino {
    const bitmap_buffer = self.allocator.alloc(u8, self.vfs.block_size) catch return AllocationError.ENOMEM;
    defer self.allocator.free(bitmap_buffer);

    const bitmap = BitSet{ .buffer = bitmap_buffer };

    const total_groups = self.vfs.blocks / self.block_per_group;
    const inode_group = first_ino / self.inode_per_group;

    for (0..total_groups) |i| {
        const group = (inode_group + i) % total_groups;

        var descriptor = try self.readBlockGroupDescriptor(group);

        if (descriptor.free_inodes == 0) continue;

        try self.read_block(descriptor.inode_bitmap_address, bitmap_buffer);

        if (bitmap.toggle_first_unset()) |bit| {
            const ino: ext2.Ino = group * self.inode_per_group + bit + 1;

            try self.write_block(descriptor.inode_bitmap_address, bitmap_buffer);
            descriptor.free_inodes -= 1;
            try self.writeBlockGroupDescriptor(group, descriptor);

            self.vfs.free_files -= 1;
            return ino;
        } else @panic("ill formed block bitmap"); // todo: fs shouldn't panic.
    }
    return error.ENOSPC;
}

pub fn free_block(self: *Self, block: ext2.BlockAddress) AllocationError!void {
    const group = block / self.block_per_group;
    const index = block % self.block_per_group;

    var descriptor = try self.readBlockGroupDescriptor(group);

    const bitmap_buffer = self.allocator.alloc(u8, self.vfs.block_size) catch return AllocationError.ENOMEM;
    try self.read_block(descriptor.block_bitmap_address, bitmap_buffer);
    const bitmap = BitSet{ .buffer = bitmap_buffer };

    if (!bitmap.is_set(index))
        @panic("double free in ext2"); // todo: fs shouldn't panic.
    bitmap.unset(index);

    try self.write_block(descriptor.block_bitmap_address, bitmap_buffer);

    descriptor.free_blocks += 1;
    try self.writeBlockGroupDescriptor(group, descriptor);
    self.vfs.free_blocks += 1;
}

pub fn free_ino(self: *Self, ino: ext2.Ino) AllocationError!void {
    const group = (ino - 1) / self.inode_per_group;
    const index = (ino - 1) % self.inode_per_group;

    var descriptor = try self.readBlockGroupDescriptor(group);

    const bitmap_buffer = self.allocator.alloc(u8, self.vfs.block_size) catch return AllocationError.ENOMEM;
    try self.read_block(descriptor.inode_bitmap_address, bitmap_buffer);
    const bitmap = BitSet{ .buffer = bitmap_buffer };

    if (!bitmap.is_set(index))
        @panic("double free in ext2"); // todo: fs shouldn't panic.
    bitmap.unset(index);

    try self.write_block(descriptor.inode_bitmap_address, bitmap_buffer);

    descriptor.free_inodes += 1;
    try self.writeBlockGroupDescriptor(group, descriptor);

    self.vfs.free_files += 1;
}

pub fn read_bitmap(self: *Self, dst: *std.bit_set.DynamicBitSet, group: usize) ReadError!void {
    const descriptor = try self.readBlockGroupDescriptor(group);
    const slice = dst.unmanaged.masks[0 .. std.math.divCeil(usize, dst.unmanaged.bit_length, @bitSizeOf(std.bit_set.DynamicBitSet.MaskInt)) catch unreachable];
    try self.read_block(descriptor.block_bitmap_address, std.mem.sliceAsBytes(slice[0..]));
}

pub fn read_block_bitmap(self: *Self, dst: *std.bit_set.DynamicBitSet, group: usize) ReadError!void {
    const descriptor = try self.readBlockGroupDescriptor(group);
    const slice = dst.unmanaged.masks[0 .. std.math.divCeil(usize, dst.unmanaged.bit_length, @bitSizeOf(std.bit_set.DynamicBitSet.MaskInt)) catch unreachable];
    try self.read_block(descriptor.block_bitmap_address, std.mem.sliceAsBytes(slice[0..]));
}

pub fn write_block_bitmap(self: *Self, dst: std.bit_set.DynamicBitSet, group: usize) WriteError!void {
    const descriptor = try self.readBlockGroupDescriptor(group);
    const slice = dst.unmanaged.masks[0 .. std.math.divCeil(usize, dst.unmanaged.bit_length, @bitSizeOf(std.bit_set.DynamicBitSet.MaskInt)) catch unreachable];
    try self.write_block(descriptor.block_bitmap_address, std.mem.sliceAsBytes(slice));
}

pub fn get_root(self: *Self) VfsSuperblock.Error.load_inode!*Inode {
    return self.retrieve_inode(ext2.RootDir);
}
