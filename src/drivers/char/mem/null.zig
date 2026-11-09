const File = @import("../../../fs/file.zig");
const char = @import("../../../device/char/char.zig");
const CharDevice = @import("../../../device/char/cdev.zig");
const CharError = char.CharError;

pub const MINOR: @import("../../../device/types.zig").minor_t = 3;

/// Singleton instance, initialized by mem.init() and lives for the entire kernel lifetime.
pub var cdev: CharDevice = undefined;

fn open(_: *CharDevice, file: *File) CharError!void {
    file.vtable = &file_vtable;
}

fn null_read(_: *File, _: []u8) File.Error.read!usize {
    // Reading from /dev/null always returns EOF (0 bytes)
    return 0;
}

fn null_write(_: *File, data: []const u8) File.Error.write!usize {
    // Writing to /dev/null always succeeds, data is discarded
    return data.len;
}

pub const ops = char.Operations{
    .open = &open,
};

pub const file_vtable = File.VTable{
    .read = &null_read,
    .write = &null_write,
    .close = &File.VTable.Generic.close,
};
