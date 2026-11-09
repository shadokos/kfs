const std = @import("std");
const Inode = @import("inode.zig");
const Errno = @import("../errno.zig").Errno;
const logger = std.log.scoped(.file);
const Cache = @import("../memory/object_allocators/slab/cache.zig").Cache;
const memory = @import("../memory.zig");

inode: *Inode,
refs: usize = 0,
pos: Pos = 0,
data: ?*anyopaque = null,
vtable: *const VTable,

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
        EINVAL,
    };
    pub const write = error{
        EBUSY,
        EIO,
        ENODEV,
        ENOMEM,
        EPERM,
        ENOSPC,
        EINVAL,
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
    pub const flush = error{
        EIO,
        ENODEV,
        EBUSY,
        EPERM,
        ENOMEM,
    };
    pub const preaddir = error{
        EBUSY,
        EIO,
        ENODEV,
        ENOMEM,
        EPERM,
    };
    pub const pread = error{
        EBUSY,
        EIO,
        ENODEV,
        ENOMEM,
        EPERM,
        ENXIO,
        EINVAL,
    };
    pub const pwrite = error{
        EBUSY,
        EIO,
        ENODEV,
        ENOMEM,
        EPERM,
        ENOSPC,
        EINVAL,
    };
};

pub const VTable = struct {
    flush: ?*const fn (*Self) Error.flush!void = null,
    pread: ?*const fn (*Self, pos: u64, buffer: []u8) Error.pread!usize = null,
    preaddir: ?*const fn (self: *Self, pos: u64, dst: *DirEnt) Error.preaddir!usize = null,
    pwrite: ?*const fn (*Self, pos: u64, buffer: []const u8) Error.pwrite!usize = null,

    close: ?*const fn (*Self) Error.close!void = null,
    read: ?*const fn (*Self, []u8) Error.read!usize = null,
    readdir: ?*const fn (*Self, *DirEnt) Error.readdir!bool = null,
    seek: ?*const fn (self: *Self, offset: Off, whence: Seek) Error.seek!Off = null,
    write: ?*const fn (*Self, []const u8) Error.write!usize = null,

    pub const Generic = struct {
        pub fn close(self: *Self) Error.close!void {
            self.inode.release();
        }

        pub fn read(self: *Self, buffer: []u8) Error.read!usize {
            const bytes_read = try self.pread(self.pos, buffer);
            self.pos += bytes_read;
            return bytes_read;
        }

        pub fn write(self: *Self, buffer: []const u8) Error.write!usize {
            const written = try self.pwrite(self.pos, buffer);
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
            const size = try self.preaddir(self.pos, dst);
            if (size == 0)
                return false;
            self.pos += size;
            return size != 0;
        }
    };
};

pub const DirEnt = Inode.DirEnt;

pub const Seek = enum {
    Set,
    Cur,
    End,
    Data,
    Hole,
};

pub const Off = i64;
pub const Pos = u64;

var cache: *Cache = undefined;

pub fn init_cache() !void {
    cache = try memory.globalCache.create(
        "file",
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

fn call_or_panic(self: *Self, comptime method: std.meta.FieldEnum(VTable), args: anytype) @typeInfo(@typeInfo(@typeInfo(std.meta.fieldInfo(VTable, method).type).optional.child).pointer.child).@"fn".return_type.? {
    if (@field(self.vtable, @tagName(method))) |f| {
        return @call(.auto, f, .{self} ++ args);
    } else {
        @panic(@tagName(method) ++ " not implemented");
    }
}

pub fn flush(self: *Self) Error.flush!void {
    return self.call_or_panic(.flush, .{});
}

pub fn pread(self: *Self, pos: u64, buffer: []u8) Error.pread!usize {
    return self.call_or_panic(.pread, .{ pos, buffer });
}

pub fn pwrite(self: *Self, pos: u64, buffer: []const u8) Error.pwrite!usize {
    return self.call_or_panic(.pwrite, .{ pos, buffer });
}

pub fn preaddir(self: *Self, pos: u64, dst: *DirEnt) Error.preaddir!usize {
    return self.call_or_panic(.preaddir, .{ pos, dst });
}

pub fn close(self: *Self) Error.close!void {
    std.debug.assert(self.refs > 0);
    self.refs -= 1;
    if (self.refs == 0) {
        try self.call_or_panic(.close, .{});
        self.destroy();
        return;
    }
}

pub fn read(self: *Self, buffer: []u8) Error.read!usize {
    return self.call_or_panic(.read, .{buffer});
}

pub fn write(self: *Self, buffer: []const u8) Error.write!usize {
    return self.call_or_panic(.write, .{buffer});
}

pub fn readdir(self: *Self, dst: *DirEnt) Error.readdir!bool {
    return self.call_or_panic(.readdir, .{dst});
}

pub fn seek(self: *Self, offset: Off, whence: Seek) Error.seek!Off {
    return self.call_or_panic(.seek, .{ offset, whence });
}

pub fn get_ref(self: *Self) *Self {
    self.refs += 1;
    return self;
}
