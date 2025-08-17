const std = @import("std");
const allocator = @import("../../../memory.zig").bigAlloc.allocator();

const core = @import("../core.zig");
const translator = core.translator;

const BlockDevice = core.BlockDevice;

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

pub const DeviceType = enum {
    HardDisk,
    CDROM,
    FloppyDisk,
    SolidStateDisk,
    RamDisk,
    Unknown,
};

pub const Features = packed struct {
    readable: bool = true,
    writable: bool = true,
    removable: bool = false,
    flushable: bool = true,
    trimable: bool = false,
};

pub const CachePolicy = enum {
    WriteThrough,
    WriteBack,
    NoCache,
};

pub const Statistics = struct {
    reads_completed: u64 = 0,
    writes_completed: u64 = 0,
    blocks_read: u64 = 0,
    blocks_written: u64 = 0,
    errors: u64 = 0,
    cache_hits: u64 = 0,
    cache_misses: u64 = 0,
};

/// Function type for performing physical I/O operations
pub const PhysicalIOFn = *const fn (
    context: *anyopaque,
    physical_block: u32,
    count: u32,
    buffer: []u8,
    is_write: bool,
) BlockError!void;

pub const Operations = struct {
    /// Physical I/O operation - operates on device's native block size
    physical_io: PhysicalIOFn,

    /// Optional operations
    flush: ?*const fn (dev: *BlockDevice) BlockError!void = null,
    trim: ?*const fn (dev: *BlockDevice, start_block: u32, count: u32) BlockError!void = null,
    media_changed: ?*const fn (dev: *BlockDevice) bool = null,
    revalidate: ?*const fn (dev: *BlockDevice) BlockError!void = null,
};

/// Type de source d'un dispositif
pub const DeviceSource = enum {
    DISK,
    CDROM,
    RAM, // RAM disk créé manuellement
    Loop, // Loop device (futur)
    Network, // iSCSI, NBD, etc. (futur)
};

/// Informations sur un dispositif enregistré
pub const RegisteredDevice = struct {
    allocator: std.mem.Allocator,
    device: *BlockDevice,
    source: DeviceSource,
    auto_discovered: bool,
    creation_params: ?[]const u8 = null,

    pub fn deinit(self: *RegisteredDevice) void {
        if (self.creation_params) |params| {
            allocator.free(params);
        }
    }
};

pub const DriveStats = struct {
    operations: u64 = 0,
    errors: u64 = 0,
    bytes_transferred: u64 = 0,
};
