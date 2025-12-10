const std = @import("std");

pub const Partition = @import("partition.zig");

pub const STANDARD_BLOCK_SIZE = 512;

pub const GenDisk = @import("gendisk.zig");

pub const translator = @import("translator.zig");
pub const BlockTranslator = translator.BlockTranslator;
pub const ScaledTranslator = translator.ScaledTranslator;
pub const IdentityTranslator = translator.IdentityTranslator;

pub const major_t = u8;
pub const minor_t = u8;

pub const dev_t = packed struct {
    minor: minor_t,
    major: major_t,

    pub fn toInt(self: dev_t) udev_t {
        return @bitCast(self);
    }

    pub fn fromInt(value: udev_t) dev_t {
        return @bitCast(value);
    }
};

// Unsigned version of dev_t
pub const udev_t = std.meta.Int(.unsigned, @bitSizeOf(dev_t));

pub const Features = packed struct {
    readonly: bool = true,
    ext_devt: bool = false, // Supports extended dev_t
    removable: bool = false,
    flushable: bool = false,
    trimable: bool = false,
};

pub const Statistics = struct {
    reads_completed: u64 = 0,
    writes_completed: u64 = 0,
    blocks_read: u64 = 0,
    blocks_written: u64 = 0,
    errors: u64 = 0,
    // TODO: Implements LRU cache
    cache_hits: u64 = 0,
    cache_misses: u64 = 0,
};

pub const BlockError = error{
    DeviceNotFound,
    AlreadyExists,
    BufferTooSmall,
    OutOfBounds,
    WriteProtected,
    NotSupported,
    IoError,
    NoFreeBuffers,
    InvalidOperation,
    MediaNotPresent,
    DeviceBusy,
    CorruptedData,
    OutOfMemory,
};

pub const IOType = enum(u1) { Read, Write };

/// Function type for performing physical I/O operations
pub const PhysicalIOFn = *const fn (
    context: *anyopaque,
    physical_block: u32,
    count: u32,
    buffer: []u8,
    operation: IOType,
) BlockError!void;

pub const Operations = struct {
    /// Physical I/O operation - operates on device's native block size
    physical_io: PhysicalIOFn,
    destroy: *const fn (*GenDisk) void,

    // /// Optional operations
    // flush: ?*const fn (dev: *BlockDevice) BlockError!void = null,
    // trim: ?*const fn (dev: *BlockDevice, start_block: u32, count: u32) BlockError!void = null,
    // media_changed: ?*const fn (dev: *BlockDevice) bool = null,
    // revalidate: ?*const fn (dev: *BlockDevice) BlockError!void = null,
    // generate_name: ?*const fn (dev: *BlockDevice) []const u8 = null,
};
