const std = @import("std");
const Inode = @import("inode.zig");
const ext2 = @import("ext2.zig");
const Errno = @import("../../errno.zig").Errno;

parent_inode: *Inode,
ino: ext2.Ino,
name: [MaxName]u8,
name_len: u8,
type: ext2.DirectoryEntry.Type,
prev_pos: ?u64,
pos: ?u64,
next_pos: u64,
end: u64,

const MaxName = 256;

const Self = @This();

pub fn init(inode: *Inode) Self {
    return .{
        .parent_inode = inode,
        .ino = undefined,
        .name = undefined,
        .name_len = 0,
        .type = undefined,
        .next_pos = 0,
        .pos = null,
        .prev_pos = null,
        .end = inode.vfs.size,
    };
}

pub fn is_last(self: Self) bool {
    return self.next_pos == self.end;
}

pub fn is_first(self: Self) bool {
    return self.prev_pos != null;
}

pub fn is_valid(self: Self) bool {
    return self.ino != 0;
}

pub fn has_name(self: Self, name: []const u8) bool {
    return self.is_valid() and std.mem.eql(u8, name, self.name[0..self.name_len]);
}

pub fn size(self: Self) u16 {
    return std.mem.alignForward(u16, self.name_len + @sizeOf(ext2.DirectoryEntry), 4);
}

pub fn cap(self: Self) u16 {
    return @intCast(self.next_pos - self.pos.?); // delta shouldn't be greater than block size in a well formed fs.
}

pub fn padding(self: Self) u16 {
    return self.cap() - self.size();
}

pub fn next(self: Self) !?Self {
    if (self.next_pos >= self.end) {
        return null;
    }

    var name_buf: [MaxName]u8 = undefined;
    var slice: []u8 = name_buf[0..];
    const next_dirent = try self.parent_inode.read_directory_entry(self.next_pos, &slice);
    if (next_dirent.size == 0) {
        @panic("corrupted");
        // return false;
    }
    return .{
        .parent_inode = self.parent_inode,
        .ino = next_dirent.inode,
        .name = name_buf,
        .name_len = @intCast(slice.len),
        .type = next_dirent.type,
        .next_pos = self.next_pos + next_dirent.size,
        .pos = self.next_pos,
        .prev_pos = self.pos,
        .end = self.end,
    };
}
