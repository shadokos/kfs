const std = @import("std");
const Superblock = @import("superblock.zig");
const VfsSuperblock = @import("../superblock.zig");
const ext2 = @import("ext2.zig");
const VfsInode = @import("../inode.zig");
const Cache = @import("../../memory/object_allocators/slab/cache.zig").Cache;
const memory = @import("../../memory.zig");
const Errno = @import("../../errno.zig").Errno;
const dev_t = @import("../../device/types.zig").dev_t;

vfs: VfsInode,
direct_block_pointer: [12]u32 = [1]u32{0} ** 12,
singly_indirect_pointer: u32 = 0,
doubly_indirect_pointer: u32 = 0,
triply_indirect_pointer: u32 = 0,

var cache: *Cache = undefined;
const Self = @This();

pub const DirectoryIterator = @import("directory_iterator.zig");

pub fn init_cache() !void {
    cache = try memory.globalCache.create(
        "ext2_inode",
        memory.directPageAllocator.page_allocator(),
        @sizeOf(Self),
        @alignOf(Self),
        6,
    );
}

pub fn create() !*Self {
    return cache.allocator().create(Self) catch error.ENOMEM;
}

pub fn destroy(self: *Self) void {
    cache.allocator().destroy(self);
}

pub fn FromVfs(vfs: *VfsInode) *Self {
    return @fieldParentPtr("vfs", vfs);
}

pub fn ToVfs(self: *Self) *VfsInode {
    return &self.vfs;
}

pub fn superblock(self: *Self) *Superblock {
    return Superblock.FromVfs(self.vfs.superblock);
}

pub fn init_and_fetch(self: *Self, sb: *Superblock, ino: VfsInode.Ino) Superblock.ReadError!void {
    self.vfs.superblock = sb.ToVfs();
    self.vfs.ino = ino;
    self.vfs.vtable = &@import("interface.zig").inode_vtable;
    self.vfs.refs = 0;
    try self.fetch();
}

pub fn init_create(self: *Self, vfs: VfsInode, type_specific: VfsSuperblock.TypeSpecificParams) (Superblock.WriteError || Superblock.ReadError || Superblock.AllocationError)!void {
    var ext2_inode: ext2.Inode = undefined;
    self.* = .{
        .vfs = vfs,
    };
    switch (self.vfs.mode.type) {
        .Regular => try self.init_regular(&ext2_inode),
        .Directory => try self.init_directory(&ext2_inode, FromVfs(type_specific.Directory.parent_ino)),
        .Link => try self.init_symlink(&ext2_inode, type_specific.Link),
        .Block => try self.init_block(&ext2_inode, type_specific.Block),
        .Character => try self.init_char(&ext2_inode, type_specific.Character),
        .Fifo, .Socket => {},
    }
    try self.superblock().writeInode(self.vfs.ino, ext2_inode);
}

pub fn fetch(self: *Self) (Superblock.ReadError || error{ENOMEM})!void {
    const ext2_ino = try self.superblock().readInode(self.vfs.ino);
    self.direct_block_pointer = ext2_ino.direct_block_pointer;
    self.singly_indirect_pointer = ext2_ino.singly_indirect_pointer;
    self.doubly_indirect_pointer = ext2_ino.doubly_indirect_pointer;
    self.triply_indirect_pointer = ext2_ino.triply_indirect_pointer;
    self.vfs.size = (@as(u64, @intCast(ext2_ino.upper_file_size)) << 32) | @as(u64, @intCast(ext2_ino.lower_size));
    self.vfs.hard_links = ext2_ino.hard_links;
    self.vfs.uid = ext2_ino.uid;
    self.vfs.gid = ext2_ino.uid;
    self.vfs.mode = ext2_ino.mode.to_vfs() orelse return error.EIO;
    self.vfs.type_specific = switch (self.vfs.mode.type) {
        .Regular => try self.fetch_regular(ext2_ino),
        .Directory => try self.fetch_directory(ext2_ino),
        .Character => try self.fetch_char(ext2_ino),
        .Block => try self.fetch_block(ext2_ino),
        .Link => try self.fetch_symlink(ext2_ino),
        .Socket => .{ .Socket = {} },
        .Fifo => .{ .Fifo = {} },
    };
}

pub fn flush(self: *Self) (Superblock.ReadError || Superblock.WriteError)!void {
    var ext2_ino = try self.superblock().readInode(self.vfs.ino);
    ext2_ino.lower_size = @truncate(self.vfs.size);
    ext2_ino.upper_file_size = @intCast(self.vfs.size >> 32);
    ext2_ino.hard_links = self.vfs.hard_links;
    ext2_ino.uid = self.vfs.uid;
    ext2_ino.gid = self.vfs.gid;
    ext2_ino.mode = ext2.Inode.Mode.from_vfs(self.vfs.mode) orelse @panic("todo");
    try switch (self.vfs.mode.type) {
        .Directory => self.flush_regular(&ext2_ino),
        .Regular => self.flush_regular(&ext2_ino),
        else => {},
    };
    try self.superblock().writeInode(self.vfs.ino, ext2_ino);
}

pub fn lookup_entry(self: *Self, name: []const u8) Superblock.ReadError!?DirectoryIterator {
    var current_entry: DirectoryIterator = DirectoryIterator.init(self);

    while (try current_entry.next()) |entry| : (current_entry = entry) {
        if (entry.has_name(name)) {
            return entry;
        }
    }
    return null;
}

pub fn lookup(self: *Self, name: []const u8) VfsSuperblock.Error.load_inode!?*Self {
    if (try self.lookup_entry(name)) |ent| {
        return self.superblock().retrieve_inode(ent.ino);
    }
    return null;
}

pub fn resolve_block_address(self: *Self, file_block: usize) Superblock.ReadError!ext2.BlockAddress {
    const pointer_per_block = self.superblock().vfs.block_size / 4;
    var actual_file_block = file_block;
    if (file_block < 12) {
        return self.direct_block_pointer[file_block];
    }
    actual_file_block -= 12;
    if (actual_file_block < pointer_per_block) {
        return self.find_in_table(actual_file_block, self.singly_indirect_pointer, 0);
    }
    actual_file_block -= pointer_per_block;
    if (actual_file_block < std.math.pow(usize, pointer_per_block, 2)) {
        return self.find_in_table(actual_file_block, self.doubly_indirect_pointer, 1);
    }
    actual_file_block -= std.math.pow(usize, pointer_per_block, 2);
    return self.find_in_table(actual_file_block, self.triply_indirect_pointer, 2);
}

fn find_in_table(self: *Self, file_block: usize, table: ext2.BlockAddress, indirection: u8) Superblock.ReadError!ext2.BlockAddress {
    const pointer_per_block = self.superblock().vfs.block_size / 4;
    const pointer_per_table = std.math.pow(usize, pointer_per_block, indirection);
    const next_table = try self.superblock().read_something(
        ext2.BlockAddress,
        table,
        (file_block / pointer_per_table) * @sizeOf(ext2.BlockAddress),
    );
    if (indirection != 0) {
        return self.find_in_table(
            file_block % pointer_per_table,
            next_table,
            indirection - 1,
        );
    }
    return next_table;
}

fn truncate_table(self: *Self, file_block: usize, table_address: ext2.BlockAddress, indirection: u8) Superblock.AllocationError!void {
    const pointer_per_block = self.superblock().vfs.block_size / 4;

    if (indirection != 0) {
        const table: []ext2.BlockAddress = self.superblock().allocator.alloc(ext2.BlockAddress, pointer_per_block) catch return Errno.ENOMEM;
        defer self.superblock().allocator.free(table);

        try self.superblock().read_block(table_address, std.mem.sliceAsBytes(table));

        const pointer_per_table = std.math.pow(usize, pointer_per_block, indirection);
        const index = file_block / pointer_per_table;
        for (0.., table[index..]) |i, *address| {
            const next_file_block = if (i == 0) file_block % pointer_per_table else 0;
            if (address.* != 0) {
                try self.truncate_table(
                    next_file_block,
                    address.*,
                    indirection - 1,
                );
            }
            if (next_file_block == 0) {
                address.* = 0;
            }
        }
    }
    if (file_block == 0) {
        try self.superblock().free_block(table_address);
    }
}

fn truncate_shrink(self: *Self, new_block_count: u32) Superblock.AllocationError!void {
    const pointer_per_block = self.superblock().vfs.block_size / 4;
    const pointer_per_double_block = std.math.pow(usize, pointer_per_block, 2);

    var first_data_block: ext2.BlockAddress = new_block_count;

    std.log.debug("new block count: {}", .{new_block_count});
    if (first_data_block < 12) {
        for (first_data_block..12) |data_block| {
            if (self.direct_block_pointer[data_block] != 0) {
                try self.truncate_table(0, self.direct_block_pointer[data_block], 0);
                self.direct_block_pointer[data_block] = 0;
            }
        }
    }
    first_data_block -|= 12;
    if (first_data_block < pointer_per_block and self.singly_indirect_pointer != 0) {
        try self.truncate_table(first_data_block, self.singly_indirect_pointer, 1);
        if (first_data_block == 0) {
            self.singly_indirect_pointer = 0;
        }
    }
    first_data_block -|= pointer_per_block;
    if (first_data_block < pointer_per_double_block and self.doubly_indirect_pointer != 0) {
        try self.truncate_table(first_data_block, self.doubly_indirect_pointer, 2);
        if (first_data_block == 0) {
            self.doubly_indirect_pointer = 0;
        }
    }
    first_data_block -|= pointer_per_double_block;
    if (self.triply_indirect_pointer != 0) {
        try self.truncate_table(first_data_block, self.triply_indirect_pointer, 3);
        if (first_data_block == 0) {
            self.triply_indirect_pointer = 0;
        }
    }
}

fn expand_table(self: *Self, first_data_block: usize, last_data_block: usize, table_address: ext2.BlockAddress, indirection: u8) Superblock.AllocationError!void {
    const pointer_per_block = self.superblock().vfs.block_size / 4;

    const table: []ext2.BlockAddress = self.superblock().allocator.alloc(ext2.BlockAddress, pointer_per_block) catch return error.ENOMEM;
    defer self.superblock().allocator.free(table);

    try self.superblock().read_block(table_address, std.mem.sliceAsBytes(table));

    if (indirection != 0) {
        const pointer_per_table = std.math.pow(usize, pointer_per_block, indirection);
        const first_index = first_data_block / pointer_per_table;
        const last_index = @min(std.math.divCeil(usize, last_data_block, pointer_per_table) catch unreachable, pointer_per_block);
        for (0.., table[first_index..last_index]) |i, *address| {
            const next_first_data_block = if (i == 0) first_data_block % pointer_per_table else 0;
            const next_last_data_block = if (i == last_index - 1) last_data_block % pointer_per_table else pointer_per_table;
            if (address.* == 0) {
                address.* = try self.superblock().alloc_block(self.vfs.ino);
            }
            try self.expand_table(
                next_first_data_block,
                next_last_data_block,
                address.*,
                indirection - 1,
            );
        }
    }
}

fn truncate_expand(self: *Self, new_block_count: u32) Superblock.AllocationError!void {
    const current_size = self.vfs.size;
    const pointer_per_block = self.superblock().vfs.block_size / 4;
    const pointer_per_double_block = std.math.pow(usize, pointer_per_block, 2);

    var first_data_block: ext2.BlockAddress = @intCast(std.math.divCeil(u64, current_size, self.superblock().vfs.block_size) catch unreachable);
    var last_data_block: ext2.BlockAddress = new_block_count;

    if (first_data_block < 12) {
        for (first_data_block..@min(12, last_data_block)) |data_block| {
            if (self.direct_block_pointer[data_block] == 0) {
                self.direct_block_pointer[data_block] = try self.superblock().alloc_block(self.vfs.ino);
            }
        }
    }

    first_data_block -|= 12;
    last_data_block -|= 12;
    if (first_data_block < pointer_per_block and last_data_block > 0) {
        if (self.singly_indirect_pointer == 0) {
            self.singly_indirect_pointer = try self.superblock().alloc_block(self.vfs.ino);
        }
        try self.expand_table(first_data_block, last_data_block, self.singly_indirect_pointer, 1);
    }
    first_data_block -|= pointer_per_block;
    last_data_block -|= pointer_per_block;
    if (first_data_block < pointer_per_double_block and last_data_block > 0) {
        if (self.doubly_indirect_pointer == 0) {
            self.doubly_indirect_pointer = try self.superblock().alloc_block(self.vfs.ino);
        }
        try self.expand_table(first_data_block, last_data_block, self.doubly_indirect_pointer, 2);
    }
    first_data_block -|= pointer_per_double_block;
    last_data_block -|= pointer_per_double_block;
    if (last_data_block > 0) {
        if (self.triply_indirect_pointer == 0) {
            self.triply_indirect_pointer = try self.superblock().alloc_block(self.vfs.ino);
        }
        try self.expand_table(first_data_block, last_data_block, self.triply_indirect_pointer, 3);
    }
}

pub fn truncate(self: *Self, new_size: u64) Superblock.AllocationError!void {
    const block_size = self.superblock().vfs.block_size;

    const current_size = self.vfs.size;

    if (current_size == new_size) {
        return;
    }

    const current_block_count: u32 = @intCast(std.math.divCeil(u64, current_size, block_size) catch unreachable);
    const new_block_count: u32 = @intCast(std.math.divCeil(u64, new_size, block_size) catch unreachable);

    if (current_block_count < new_block_count) {
        try self.truncate_expand(new_block_count);
    } else if (current_block_count > new_block_count) {
        try self.truncate_shrink(new_block_count);
    }

    self.vfs.size = new_size;
}

pub fn read_directory_entry(self: *Self, pos: u64, name: ?*[]u8) Superblock.ReadError!ext2.DirectoryEntry {
    var ret: ext2.DirectoryEntry = undefined;
    if (try self.pread(pos, std.mem.asBytes(&ret)) != @sizeOf(ext2.DirectoryEntry))
        return error.EIO;
    if (name) |name_slice| {
        const name_len = @min(ret.name_length, name_slice.*.len); // todo: remove magic number
        name_slice.* = name_slice.*[0..name_len];
        if (try self.pread(
            pos + @offsetOf(ext2.DirectoryEntry, "name"),
            name_slice.*,
        ) != name_len)
            return error.EIO;
    }
    return ret;
}

pub fn write_directory_entry(self: *Self, pos: u64, entry: ext2.DirectoryEntry, name: []const u8) Superblock.ReadError!void {
    if (try self.pwrite(pos, std.mem.asBytes(&entry)) != @sizeOf(ext2.DirectoryEntry))
        return error.EIO;
    if (try self.pwrite(
        pos + @offsetOf(ext2.DirectoryEntry, "name"),
        name,
    ) != name.len)
        return error.EIO;
}

pub fn remove_entry(self: *Self, name: []const u8) (Superblock.WriteError || Superblock.ReadError || error{EPERM})!bool {
    const entry = try self.lookup_entry(name) orelse return false;
    const block_size = self.superblock().vfs.block_size;

    if (entry.type == .directory) {
        return Errno.EPERM; // todo: maybe this should already be sanitized at this point, is it the reponsibility of the fs driver or the os?
    }

    if (entry.pos.? % block_size != 0) { // not first entry of block
        const prev_pos = entry.prev_pos.?;
        const prev_block = try self.resolve_block_address(@intCast(prev_pos / block_size));
        const prev_index: u32 = @intCast(prev_pos % block_size);
        var prev_dirent = try self.superblock().read_something(ext2.DirectoryEntry, prev_block, prev_index);
        prev_dirent.size += @intCast(entry.next_pos - entry.pos.?);
        try self.superblock().write_something(prev_dirent, prev_block, prev_index);
    } else { // first entry of block
        const current_block = try self.resolve_block_address(@intCast(entry.pos.? / block_size));
        try self.superblock().write_something(ext2.DirectoryEntry{
            .inode = 0,
            .name_length = 0,
            .size = @intCast(entry.next_pos - entry.pos.?),
            .type = undefined,
            .name = undefined,
        }, current_block, 0);
    }
    const target_inode = try self.superblock().retrieve_inode(entry.ino);
    defer target_inode.vfs.release();
    target_inode.vfs.hard_links -= 1;
    return true;
}

pub fn add_entry(self: *Self, name: []const u8, target: *Self) (Superblock.WriteError || Superblock.ReadError || Superblock.AllocationError || error{EEXIST})!void {
    const block_size = self.superblock().vfs.block_size;
    const new_entry_size = @sizeOf(ext2.DirectoryEntry) + name.len;
    var candidate: ?DirectoryIterator = null;
    var it = DirectoryIterator.init(self);

    while (try it.next()) |next| : (it = next) {
        if (next.has_name(name)) {
            return Errno.EEXIST;
            // todo: already an entry with this name, we need to decide who has the responsibility to check that
        }
        const available_space = if (next.is_valid()) next.padding() else next.cap();
        const candidate_available_space = if (candidate) |ce| (if (ce.is_valid()) ce.padding() else ce.cap()) else 0;
        const is_large_enough = available_space >= new_entry_size;
        const is_better = candidate == null or available_space < candidate_available_space;
        if (is_large_enough and is_better) {
            candidate = next;
        }
    }
    if (candidate) |entry| {
        if (entry.is_valid()) { // We split this entry between A and B.
            const current_block = try self.resolve_block_address(@intCast(entry.pos.? / block_size));
            const A_index: u32 = @intCast(entry.pos.? % block_size);
            const B_index: u32 = A_index + entry.size();

            // Write A
            try self.superblock().write_something(ext2.DirectoryEntry{
                .inode = entry.ino,
                .name_length = entry.name_len,
                .size = entry.size(),
                .type = entry.type,
                .name = undefined,
            }, current_block, A_index);
            try self.superblock().write_bytes(entry.name[0..entry.name_len], current_block, A_index + @sizeOf(ext2.DirectoryEntry));
            // todo: we want one atomic write for this.

            // Write B
            try self.superblock().write_something(ext2.DirectoryEntry{
                .inode = target.vfs.ino,
                .name_length = @intCast(name.len),
                .size = entry.padding(),
                .type = ext2.inode_type_to_dir_ent_type(ext2.Inode.Type.from_vfs(target.vfs.mode.type) orelse @panic("todo")),
                .name = undefined,
            }, current_block, B_index);
            try self.superblock().write_bytes(name, current_block, B_index + @sizeOf(ext2.DirectoryEntry));
        } else { // We rewrite this invalid entry.
            const current_block = try self.resolve_block_address(@intCast(entry.pos.? / block_size));
            const index: u32 = @intCast(entry.pos.? % block_size);
            try self.superblock().write_something(ext2.DirectoryEntry{
                .inode = target.vfs.ino,
                .name_length = @intCast(name.len),
                .size = entry.size(),
                .type = ext2.inode_type_to_dir_ent_type(ext2.Inode.Type.from_vfs(target.vfs.mode.type) orelse @panic("todo")),
                .name = undefined,
            }, current_block, index);
            try self.superblock().write_bytes(name, current_block, index + @sizeOf(ext2.DirectoryEntry));
        }
    } else { // We add a new block at the end of a directory with a single entry.
        try self.truncate(it.end + block_size); // todo: maybe have another block wise method
        const new_block = try self.resolve_block_address(@intCast(it.end / block_size));
        try self.superblock().write_something(ext2.DirectoryEntry{
            .inode = target.vfs.ino,
            .name_length = @intCast(name.len),
            .size = @intCast(block_size),
            .type = ext2.inode_type_to_dir_ent_type(ext2.Inode.Type.from_vfs(target.vfs.mode.type) orelse @panic("todo")),
            .name = undefined,
        }, new_block, 0);
        try self.superblock().write_bytes(name, new_block, @sizeOf(ext2.DirectoryEntry));
    }
    target.vfs.hard_links += 1;
}

fn init_directory(self: *Self, ext2_inode: *ext2.Inode, parent: *Self) (Superblock.WriteError || Superblock.ReadError || Superblock.AllocationError)!void {
    try self.init_regular(ext2_inode);
    //todo: can we do that atomically?
    self.add_entry(".", self) catch |e| switch (e) {
        error.EEXIST => unreachable,
        else => |e2| return e2,
    };
    self.add_entry("..", parent) catch |e| switch (e) {
        error.EEXIST => unreachable,
        else => |e2| return e2,
    };
}

fn init_regular(self: *Self, ext2_inode: *ext2.Inode) error{}!void {
    @memset(self.direct_block_pointer[0..], 0);
    self.singly_indirect_pointer = 0;
    self.doubly_indirect_pointer = 0;
    self.triply_indirect_pointer = 0;
    @memset(ext2_inode.direct_block_pointer[0..], 0);
    ext2_inode.singly_indirect_pointer = 0;
    ext2_inode.doubly_indirect_pointer = 0;
    ext2_inode.triply_indirect_pointer = 0;
    self.vfs.size = 0;
}

fn init_symlink(self: *Self, ext2_inode: *ext2.Inode, value: []const u8) (Superblock.WriteError || Superblock.AllocationError || error{ENOMEM})!void {
    self.vfs.type_specific = .{ .Link = memory.smallAlloc.allocator().dupe(u8, value) catch return Errno.ENOMEM };
    const size = value.len;

    if (size >= 60) {
        try self.init_regular(ext2_inode);
        if (try self.pwrite(0, value) != size) {
            return Errno.EIO;
        }
    } else {
        const ptr: [*]u8 = @ptrCast(&ext2_inode.direct_block_pointer);
        @memcpy(ptr[0..size], value);
    }
    self.vfs.size = size;
}

fn init_char(self: *Self, ext2_inode: *ext2.Inode, device: dev_t) error{}!void {
    self.vfs.type_specific = .{ .Character = device };
    ext2_inode.direct_block_pointer[0] = @intCast(device.toInt());
}

fn init_block(self: *Self, ext2_inode: *ext2.Inode, device: dev_t) error{}!void {
    self.vfs.type_specific = .{ .Block = device };
    ext2_inode.direct_block_pointer[0] = @intCast(device.toInt());
}

fn flush_regular(self: *Self, ext2_inode: *ext2.Inode) error{}!void {
    ext2_inode.direct_block_pointer = self.direct_block_pointer;
    ext2_inode.singly_indirect_pointer = self.singly_indirect_pointer;
    ext2_inode.doubly_indirect_pointer = self.doubly_indirect_pointer;
    ext2_inode.triply_indirect_pointer = self.triply_indirect_pointer;
}

fn copy_tables(self: *Self, ext2_inode: ext2.Inode) void {
    self.direct_block_pointer = ext2_inode.direct_block_pointer;
    self.singly_indirect_pointer = ext2_inode.singly_indirect_pointer;
    self.doubly_indirect_pointer = ext2_inode.doubly_indirect_pointer;
    self.triply_indirect_pointer = ext2_inode.triply_indirect_pointer;
}

fn fetch_regular(self: *Self, ext2_inode: ext2.Inode) error{}!VfsInode.TypeSpecificData {
    self.copy_tables(ext2_inode);

    return .{ .Regular = {} };
}

fn fetch_directory(self: *Self, ext2_inode: ext2.Inode) error{}!VfsInode.TypeSpecificData {
    self.copy_tables(ext2_inode);

    return .{ .Directory = .{} };
}

fn fetch_symlink(self: *Self, ext2_inode: ext2.Inode) (Superblock.ReadError || error{ ENOMEM, EIO })!VfsInode.TypeSpecificData {
    const size = self.vfs.size;
    if (size < 60) {
        const ptr: [*]const u8 = @ptrCast(&ext2_inode.direct_block_pointer);
        const link = self.superblock().allocator.dupe(u8, ptr[0..@intCast(size)]) catch return Errno.ENOMEM;
        return .{ .Link = link };
    } else {
        // todo: add a limit on symlink size
        const buffer = self.superblock().allocator.alloc(u8, @intCast(size)) catch return Errno.ENOMEM;
        errdefer self.superblock().allocator.free(buffer);
        if (try self.pread(0, buffer) != buffer.len) // todo: Investigate the need and feasibility for an atomic read.
            return Errno.EIO;
        return .{ .Link = buffer };
    }
}

fn fetch_char(_: *Self, ext2_inode: ext2.Inode) error{}!VfsInode.TypeSpecificData {
    return .{ .Character = @bitCast(@as(u16, @truncate(ext2_inode.direct_block_pointer[0]))) };
}

fn fetch_block(_: *Self, ext2_inode: ext2.Inode) error{}!VfsInode.TypeSpecificData {
    return .{ .Block = @bitCast(@as(u16, @truncate(ext2_inode.direct_block_pointer[0]))) };
}

pub fn pread(self: *Self, pos: u64, buffer: []u8) (Superblock.ReadError)!usize {
    const block_size = self.superblock().vfs.block_size;
    var buffer_pos: usize = 0;
    const file_size = self.vfs.size;

    const actual_len = @min(file_size - pos, buffer.len);

    while (buffer_pos < actual_len) {
        const absolute_pos = pos + buffer_pos;
        const file_block: usize = @intCast(absolute_pos / block_size);
        const chunk_begin: usize = @intCast(absolute_pos % block_size);
        const chunk_end = @min(block_size, chunk_begin + actual_len - buffer_pos);

        const logical_block = try self.resolve_block_address(file_block);
        try self.superblock().read_bytes(buffer[buffer_pos..][0 .. chunk_end - chunk_begin], logical_block, chunk_begin);
        buffer_pos += chunk_end - chunk_begin;
    }

    return buffer_pos;
}

pub fn ensure_space(self: *Self, new_size: u64) Superblock.AllocationError!void {
    const current_size = self.vfs.size;

    if (new_size > current_size) {
        try self.truncate(new_size);
    }
}

pub fn pwrite(self: *Self, pos: u64, buffer: []const u8) (Superblock.WriteError || Superblock.AllocationError)!usize {
    const current_size = self.vfs.size;
    const new_size = @max(pos + buffer.len, current_size);
    try self.ensure_space(new_size);

    const block_size = self.superblock().vfs.block_size;
    var buffer_pos: usize = 0;
    var file_pos: u64 = pos;

    const actual_len = buffer.len;

    while (buffer_pos < actual_len) {
        const file_block: usize = @intCast(file_pos / block_size);
        const chunk_begin: usize = @intCast(file_pos % block_size);
        const chunk_end: usize = @min(block_size, chunk_begin + actual_len - buffer_pos);

        const logical_block = try self.resolve_block_address(file_block);
        try self.superblock().write_bytes(buffer[buffer_pos..][0 .. chunk_end - chunk_begin], logical_block, chunk_begin);
        buffer_pos += chunk_end - chunk_begin;
        file_pos += chunk_end - chunk_begin;
    }

    return buffer_pos;
}
