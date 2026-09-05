const File = @import("../../../fs/file.zig");
const char = @import("../../../device/char/char.zig");
const CharDevice = @import("../../../device/char/cdev.zig");
const CharError = char.CharError;

pub const MINOR: @import("../../../device/types.zig").minor_t = 5;

/// Singleton instance, initialized by mem.init() and lives for the entire kernel lifetime.
pub var cdev: CharDevice = undefined;

fn open(_: *CharDevice, file: *File) CharError!void {
    file.vtable = &file_vtable;
}

fn zero_read(_: *File, buf: []u8) File.Error.read!usize {
    @memset(buf, 0);
    return buf.len;
}

fn zero_write(_: *File, data: []const u8) File.Error.write!usize {
    return data.len;
}

pub const ops = char.Operations{
    .open = &open,
};

pub const file_vtable = File.VTable{
    .read = &zero_read,
    .write = &zero_write,
    .close = &File.VTable.Generic.close,
};
