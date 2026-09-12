const File = @import("../fs/file.zig");
const Errno = @import("../errno.zig").Errno;

files: [1024]?*File = [1]?*File{null} ** 1024,

pub const Fd = i32;

const Self = @This();

pub fn reset(self: *Self) !void {
    for (self.files[0..]) |*opt_file| {
        if (opt_file.*) |file| {
            try file.close();
            opt_file.* = null;
        }
    }
}

pub fn clone(self: Self) Self {
    var ret = Self{};

    for (self.files[0..], ret.files[0..]) |old, *new| {
        if (old) |f| {
            new.* = f.get_ref();
        }
    }
    return ret;
}

pub fn get(self: *Self, fd: Fd) !*File {
    if (fd < 0 or fd >= self.files.len) {
        return error.EBADF;
    }
    return self.files[@intCast(fd)] orelse return error.EBADF;
}

pub fn add(self: *Self, file: *File, start : Fd) !Fd {
    for (self.files[@intCast(start)..], @intCast(start)..) |*f, fd| {
        if (f.* == null) {
            f.* = file;
            return @intCast(fd);
        }
    }
    return Errno.EMFILE;
}

pub fn set(self: *Self, fd: Fd, file: *File) !void {
    if (fd < 0 or fd >= self.files.len) {
        return error.EBADF;
    }
    if (self.files[@intCast(fd)]) |old_file| {
        try old_file.close();
    }
    self.files[@intCast(fd)] = file;
    file.refs += 1;
}

pub fn remove(self: *Self, fd: Fd) !void {
    if (fd < 0 or fd >= self.files.len) {
        return error.EBADF;
    }
    if (self.files[@intCast(fd)]) |f| {
        try f.*.close();
        self.files[@intCast(fd)] = null;
    }
}
