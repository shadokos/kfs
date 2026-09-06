const std = @import("std");
const Inode = @import("inode.zig");
const File = @import("file.zig");
const memory = @import("../memory.zig");

pub fn open(base: *Inode, file: *File) Inode.Error.open!void {
    file.* = .{
        .inode = base.get_ref(),
        .vtable = &file_vtable,
        .refs = 1,
    };
    if (file.inode.type_specific.Fifo == null) {
        file.inode.type_specific.Fifo = .{
            .buffer = memory.smallAlloc.alloc(u8, 1024) catch return error.ENOMEM,
            .head = 0,
            .tail = 0,
        };
    }
}

fn write(self: *File, buffer: []const u8) File.Error.write!usize {
    if (self.inode.type_specific.Fifo) |*fifo| {
        const written = @min(fifo.buffer.len - fifo.head, buffer.len);
        @memcpy(fifo.buffer[fifo.head..][0..written], buffer[0..written]);
        fifo.head += written;
        return written;
    }
    return 0;
}

fn read(self: *File, buffer: []u8) File.Error.read!usize {
    if (self.inode.type_specific.Fifo) |*fifo| {
        const bytes_read = @min(fifo.head, buffer.len);
        @memcpy(buffer[0..bytes_read], fifo.buffer[0..bytes_read]);
        @memmove(fifo.buffer[0 .. fifo.head - bytes_read], fifo.buffer[bytes_read..fifo.head]);
        fifo.head -= bytes_read;
        return bytes_read;
    }
    return 0;
}

fn close(_: *File) File.Error.close!void {}

pub const file_vtable: File.VTable = .{
    .close = &close,
    .read = &read,
    .write = &write,
};
