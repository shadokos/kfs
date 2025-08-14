const std = @import("std");
const BlockDeviceManager = @import("device_manager.zig");
const BufferCache = @import("buffer_cache.zig");
const Buffer = @import("buffer_cache.zig").Buffer;
const logger = std.log.scoped(.block_device);

const Self = @This();
const Error = @import("block.zig").Error;

// === BLOCK DEVICE INTERFACE ===

// Device identification
name: [16]u8,
device_type: DeviceType,

// Device characteristics
block_size: u32, // Usually 512 for HDD, 2048 for CD-ROM
total_blocks: u64, // Total number of blocks
max_transfer: u32, // Maximum blocks per transfer

// Device capabilities
features: Features,

// Operations vtable
ops: *const Operations,

// Driver-specific data
private_data: ?*anyopaque = null,

// Statistics
stats: Statistics = .{},

// Cache hint
cache_policy: CachePolicy = .WriteBack,

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
    WriteThrough, // Write to device immediately
    WriteBack, // Write to cache, flush later
    NoCache, // Bypass cache entirely
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

pub const Operations = struct {
    // Core operations
    read: *const fn (dev: *Self, start_block: u64, count: u32, buffer: []u8) Error!void,
    write: *const fn (dev: *Self, start_block: u64, count: u32, buffer: []const u8) Error!void,
    flush: ?*const fn (dev: *Self) Error!void = null,

    // Optional operations
    trim: ?*const fn (dev: *Self, start_block: u64, count: u32) Error!void = null,
    get_info: ?*const fn (dev: *Self) DeviceInfo = null,
    media_changed: ?*const fn (dev: *Self) bool = null,
    revalidate: ?*const fn (dev: *Self) Error!void = null,
};

pub const DeviceInfo = struct {
    vendor: []const u8,
    model: []const u8,
    serial: []const u8,
    firmware_version: []const u8,
    supports_dma: bool,
    current_speed: u32, // MB/s
};

// === PUBLIC METHODS ===

pub fn read(self: *Self, start_block: u64, count: u32, buffer: []u8) Error!void {
    if (buffer.len < count * self.block_size) return Error.BufferTooSmall;
    if (start_block + count > self.total_blocks) return Error.OutOfBounds;
    if (!self.features.readable) return Error.NotSupported;

    try self.ops.read(self, start_block, count, buffer);

    self.stats.reads_completed += 1;
    self.stats.blocks_read += count;
}

pub fn write(self: *Self, start_block: u64, count: u32, buffer: []const u8) Error!void {
    if (buffer.len < count * self.block_size) return Error.BufferTooSmall;
    if (start_block + count > self.total_blocks) return Error.OutOfBounds;
    if (!self.features.writable) return Error.WriteProtected;

    try self.ops.write(self, start_block, count, buffer);

    self.stats.writes_completed += 1;
    self.stats.blocks_written += count;
}

pub fn flush(self: *Self) Error!void {
    if (self.ops.flush) |flush_fn| {
        try flush_fn(self);
    }
}

pub fn trim(self: *Self, start_block: u64, count: u32) Error!void {
    if (!self.features.supports_trim) return Error.NotSupported;
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

// === GLOBAL INSTANCES ===

var device_manager: BlockDeviceManager = undefined;
var buffer_cache: BufferCache = undefined;

pub fn init() !void {
    device_manager = BlockDeviceManager.init();
    buffer_cache = try BufferCache.init();
    logger.info("Block device layer initialized", .{});
}

pub fn deinit() void {
    buffer_cache.deinit();
    device_manager.deinit();
}

pub fn getManager() *BlockDeviceManager {
    return &device_manager;
}

pub fn getCache() *BufferCache {
    return &buffer_cache;
}
