const constants = @import("constants.zig");
const Channel = @import("channel.zig");

// === COMMON TYPES ===

/// IDE/ATAPI error types
pub const Error = error{
    InvalidDrive,
    DriveNotPresent,
    InvalidCount,
    BufferTooSmall,
    Timeout,
    ReadTimeout,
    WriteTimeout,
    ReadError,
    WriteError,
    OutOfBounds,
    NotInitialized,
    Interrupted,
    OutOfMemory,
    TimeoutTooLong,
    NoControllerFound,
    PCIError,

    // IDE-specific errors
    BadBlock,
    UncorrectableError,
    MediaChanged,
    SectorNotFound,
    MediaChangeRequested,
    CommandAborted,
    Track0NotFound,
    AddressMarkNotFound,
    UnknownError,

    // ATAPI-specific errors
    NoMedia,
    MediaNotReady,
    InvalidPacket,
    PacketTooLarge,
};

/// Drive type enumeration
pub const DriveType = enum {
    ATA, // Traditional hard disk
    ATAPI, // CD-ROM, DVD, etc.
    Unknown,

    pub fn toString(self: DriveType) []const u8 {
        return switch (self) {
            .ATA => "ATA",
            .ATAPI => "ATAPI",
            .Unknown => "Unknown",
        };
    }
};

/// Channel type enumeration
pub const Unit = enum {
    bytes,
    Kb,
    Mb,
    Gb,
};

/// Capacity structure for drive information
pub const Capacity = struct {
    const Self = @This();

    sectors: u64, // Total number of sectors
    sector_size: u32, // Size of each sector in bytes
    unit: Unit = .bytes, // Default unit is bytes

    pub fn totalSizeAutoUnit(self: *const Capacity) u64 {
        return switch (self.unit) {
            .bytes => self.totalSize(),
            .Kb => self.totalSize() >> 10,
            .Mb => self.totalSize() >> 20,
            .Gb => self.totalSize() >> 30,
        };
    }

    pub fn totalSize(self: *const Capacity) u64 {
        return self.sectors * self.sector_size;
    }

    pub fn init(sectors: u64, sector_size: u32) Capacity {
        var ret = Capacity{
            .sectors = sectors,
            .sector_size = sector_size,
        };
        ret.unit = if (ret.totalSize() == 0)
            .bytes
        else switch (@import("std").math.log2(ret.totalSize())) {
            0...9 => .bytes,
            10...19 => .Kb,
            20...29 => .Mb,
            else => .Gb,
        };
        return ret;
    }
};

/// Drive information structure
pub const DriveInfo = struct {
    drive_type: DriveType,
    channel: ChannelType,
    drive: DrivePosition,
    model: [41]u8,
    capacity: Capacity,
    removable: bool, // true for ATAPI generally

    pub const ChannelType = enum { Primary, Secondary };
    pub const DrivePosition = enum { Master, Slave };

    /// Check if this is an ATAPI drive
    pub fn isATAPI(self: DriveInfo) bool {
        return self.drive_type == .ATAPI;
    }

    /// Check if this is an ATA drive
    pub fn isATA(self: DriveInfo) bool {
        return self.drive_type == .ATA;
    }
};

/// IDE request structure for asynchronous operations
pub const Request = struct {
    channel: DriveInfo.ChannelType,
    drive: DriveInfo.DrivePosition,
    command: u8,
    lba: u32,
    count: u16,
    buffer: union {
        read: []u8,
        write: []const u8,
        packet: []const u8,
    },
    current_sector: usize = 0,
    err: ?Error = null,
    completed: bool = false,
    timed_out: bool = false,
    timeout_ms: ?usize = null, // Store timeout value instead of event
    timeout_event_id: ?u64 = null, // Store event ID for cancellation

    // ATAPI-specific fields
    packet_data: ?[constants.ATAPI.PACKET_SIZE]u8 = null,
    is_atapi: bool = false,
};
