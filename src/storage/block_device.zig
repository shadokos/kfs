const std = @import("std");
const logger = std.log.scoped(.block_device);

pub const BlockError = error{
DeviceNotFound,
DeviceExists,
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
    supports_flush: bool = false,
    supports_trim: bool = false,
    supports_barriers: bool = false,
    _padding: u2 = 0,
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

pub const DeviceInfo = struct {
    vendor: []const u8,
    model: []const u8,
    serial: []const u8,
    firmware_version: []const u8,
    supports_dma: bool,
    current_speed: u32,
};

pub const Operations = struct {
    read: *const fn (dev: *BlockDevice, start_block: u64, count: u32, buffer: []u8) BlockError!void,
    write: *const fn (dev: *BlockDevice, start_block: u64, count: u32, buffer: []const u8) BlockError!void,
    flush: ?*const fn (dev: *BlockDevice) BlockError!void = null,
    trim: ?*const fn (dev: *BlockDevice, start_block: u64, count: u32) BlockError!void = null,
    get_info: ?*const fn (dev: *BlockDevice) DeviceInfo = null,
    media_changed: ?*const fn (dev: *BlockDevice) bool = null,
    revalidate: ?*const fn (dev: *BlockDevice) BlockError!void = null,
};

pub const BlockDevice = struct {
    name: [16]u8,
    device_type: DeviceType,
    block_size: u32,
    total_blocks: u64,
    max_transfer: u32,
    features: Features,
    ops: *const Operations,
    private_data: ?*anyopaque = null,
    stats: Statistics = .{},
    cache_policy: CachePolicy = .WriteBack,

    const Self = @This();

    pub fn read(self: *Self, start_block: u64, count: u32, buffer: []u8) BlockError!void {
        if (buffer.len < count * self.block_size) return BlockError.BufferTooSmall;
        if (start_block + count > self.total_blocks) return BlockError.OutOfBounds;
        if (!self.features.readable) return BlockError.NotSupported;

        try self.ops.read(self, start_block, count, buffer);

        self.stats.reads_completed += 1;
        self.stats.blocks_read += count;
    }

    pub fn write(self: *Self, start_block: u64, count: u32, buffer: []const u8) BlockError!void {
        if (buffer.len < count * self.block_size) return BlockError.BufferTooSmall;
        if (start_block + count > self.total_blocks) return BlockError.OutOfBounds;
        if (!self.features.writable) return BlockError.WriteProtected;

        try self.ops.write(self, start_block, count, buffer);

        self.stats.writes_completed += 1;
        self.stats.blocks_written += count;
    }

    pub fn flush(self: *Self) BlockError!void {
        if (self.ops.flush) |flush_fn| {
            try flush_fn(self);
        }
    }

    pub fn trim(self: *Self, start_block: u64, count: u32) BlockError!void {
        if (!self.features.supports_trim) return BlockError.NotSupported;
        if (self.ops.trim) |trim_fn| {
            try trim_fn(self, start_block, count);
        }
    }

    pub fn getName(self: *const Self) []const u8 {
        for (self.name, 0..) |c, i| {
            if (c == 0) return self.name[0..i];
        }
        return &self.name;
    }

    pub fn getInfo(self: *Self) ?DeviceInfo {
        if (self.ops.get_info) |get_info_fn| {
            return get_info_fn(self);
        }
        return null;
    }

    pub fn mediaChanged(self: *Self) bool {
        if (self.ops.media_changed) |media_changed_fn| {
            return media_changed_fn(self);
        }
        return false;
    }

    pub fn revalidate(self: *Self) BlockError!void {
        if (self.ops.revalidate) |revalidate_fn| {
            try revalidate_fn(self);
        }
    }
};