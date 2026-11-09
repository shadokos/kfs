const std = @import("std");
const Inode = @import("inode.zig");
const File = @import("file.zig");
const memory = @import("../memory.zig");
const registry = @import("../device/block/registry.zig");
const block_core = @import("../device/block/block.zig");

pub fn open(base: *Inode, file: *File) Inode.Error.open!void {
    file.* = .{
        .inode = base.get_ref(),
        .vtable = &file_vtable,
        .refs = 1,
        .data = registry.get_partition(base.type_specific.Block) orelse return error.ENXIO,
    };
}

fn pread(file: *File, pos: u64, buffer: []u8) File.Error.pread!usize {
    const part: *block_core.Partition = @ptrCast(@alignCast(file.data.?));
    if (!std.mem.isAligned(buffer.len, block_core.STANDARD_BLOCK_SIZE) or
        !std.mem.isAlignedGeneric(File.Pos, pos, block_core.STANDARD_BLOCK_SIZE))
    {
        return error.EINVAL;
    }
    // todo: harmonize size type (64 or 32)
    // todo: we want the read size here.
    // todo: translate block error
    part.read(@intCast(pos / block_core.STANDARD_BLOCK_SIZE), buffer.len / block_core.STANDARD_BLOCK_SIZE, buffer) catch return error.EIO;
    return buffer.len;
}

fn pwrite(file: *File, pos: u64, buffer: []const u8) File.Error.pwrite!usize {
    const part: *block_core.Partition = @ptrCast(@alignCast(file.data.?));
    if (!std.mem.isAligned(buffer.len, block_core.STANDARD_BLOCK_SIZE) or
        !std.mem.isAlignedGeneric(File.Pos, pos, block_core.STANDARD_BLOCK_SIZE))
    {
        return error.EINVAL;
    }
    // todo: harmonize size type (64 or 32)
    // todo: we want the written size here.
    // todo: translate block error
    part.write(@intCast(pos / block_core.STANDARD_BLOCK_SIZE), buffer.len / block_core.STANDARD_BLOCK_SIZE, buffer) catch return error.EIO;
    return buffer.len;
}

fn close(file: *File) File.Error.close!void {
    file.inode.release();
}

pub const file_vtable: File.VTable = .{
    .pread = &pread,
    .pwrite = &pwrite,
    .close = &close,
    .write = File.VTable.Generic.write,
    .read = File.VTable.Generic.read,
    .seek = File.VTable.Generic.seek,
};
