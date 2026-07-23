const std = @import("std");
const Inode = @import("inode.zig");
const Errno = @import("../errno.zig").Errno;
const logger = std.log.scoped(.file);
const Cache = @import("../memory/object_allocators/slab/cache.zig").Cache;
const memory = @import("../memory.zig");

inode: *Inode,
refs: usize = 0,
pos: u64 = 0,
vtable: *const VTable = &default_vtable,

pub const Options = struct {
    read: bool = false,
    write: bool = false,
    append: bool = false,
};

const Self = @This();

pub const Error = struct {
    pub const close = error{};
    pub const read = error{
        EBUSY,
        EIO,
        ENODEV,
        ENOMEM,
        EPERM,
        ENXIO,
    };
    pub const write = error{
        EBUSY,
        EIO,
        ENODEV,
        ENOMEM,
        EPERM,
        ENOSPC,
    };
    pub const readdir = error{
        EBUSY,
        EIO,
        ENODEV,
        ENOMEM,
        EPERM,
    };
    pub const seek = error{
        EOVERFLOW,
        EINVAL,
    };
};

pub const VTable = struct {
    close: *const fn (*Self) Error.close!void = &Generic.close,
    read: *const fn (*Self, []u8) Error.read!usize = &Generic.read,
    readdir: *const fn (*Self, *DirEnt) Error.readdir!bool = &Generic.readdir,
    seek: *const fn (self: *Self, offset: Off, whence: Seek) Error.seek!Off = &Generic.seek,
    write: *const fn (*Self, []const u8) Error.write!usize = &Generic.write,
};
const default_vtable = VTable{};

pub const DirEnt = Inode.DirEnt;

pub const Seek = enum {
    Set,
    Cur,
    End,
    Data,
    Hole,
};

pub const Off = i64;

var cache: *Cache = undefined;

pub fn init_cache() !void {
    cache = try memory.globalCache.create(
        "vfs_file",
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

pub fn close(self: *Self) Error.close!void {
    return self.vtable.close(self);
}

pub fn read(self: *Self, buffer: []u8) Error.read!usize {
    return self.vtable.read(self, buffer);
}

pub fn write(self: *Self, buffer: []const u8) Error.write!usize {
    return self.vtable.write(self, buffer);
}

pub fn readdir(self: *Self, dst: *DirEnt) Error.readdir!bool {
    return self.vtable.readdir(self, dst);
}

pub fn seek(self: *Self, offset: Off, whence: Seek) Error.seek!Off {
    return self.vtable.seek(self, offset, whence);
}

pub const Generic = struct {
    pub fn close(self: *Self) Error.close!void {
        self.inode.release();
    }

    pub fn read(self: *Self, buffer: []u8) Error.read!usize {
        const bytes_read = try self.inode.pread(self.pos, buffer);
        self.pos += bytes_read;
        return bytes_read;
    }

    pub fn write(self: *Self, buffer: []const u8) Error.write!usize {
        const written = try self.inode.pwrite(self.pos, buffer);
        self.pos += written;
        return written;
    }

    pub fn seek(self: *Self, offset: Off, whence: Seek) Error.seek!Off {
        const new_pos: i66 = switch (whence) {
            .Cur => self.pos + @as(i66, @intCast(offset)),
            .End, .Hole => self.inode.size + @as(i66, @intCast(offset)),
            .Set, .Data => @as(i66, @intCast(offset)),
        };
        if (new_pos < 0 or new_pos > std.math.maxInt(@TypeOf(self.pos)))
            return Errno.EINVAL;
        self.pos = @intCast(new_pos);
        return if (self.pos <= std.math.maxInt(Off)) @intCast(self.pos) else return Errno.EOVERFLOW;
    }

    pub fn readdir(self: *Self, dst: *DirEnt) Error.readdir!bool {
        if (self.pos == self.inode.size)
            return false;
        const size = try self.inode.preaddir(self.pos, dst);
        self.pos += size;
        return size != 0;
    }
};
