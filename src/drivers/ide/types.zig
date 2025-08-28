const Channel = @import("channel.zig");

pub const Buffer = union {
    read: []u8,
    write: []const u8,
};

pub const IDEError = error{
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
    NotSupported,

    BadBlock,
    UncorrectableError,
    MediaChanged,
    SectorNotFound,
    MediaChangeRequested,
    CommandAborted,
    Track0NotFound,
    AddressMarkNotFound,
    UnknownError,

    NoMedia,
    MediaNotReady,
    InvalidPacket,
    PacketTooLarge,
};

pub const DriveType = enum {
    ATA,
    ATAPI,
    Unknown,

    pub fn toString(self: DriveType) []const u8 {
        return switch (self) {
            .ATA => "ATA",
            .ATAPI => "ATAPI",
            .Unknown => "Unknown",
        };
    }
};

pub const Capacity = struct {
    sectors: u32,
    sector_size: u32,

    pub fn totalSize(self: *const Capacity) u64 {
        return self.sectors * self.sector_size;
    }
};

pub const DriveInfo = struct {
    drive_type: DriveType,
    channel: Channel.ChannelType,
    position: Channel.DrivePosition,
    model: [41]u8,
    capacity: Capacity,
    removable: bool,

    pub fn isATAPI(self: DriveInfo) bool {
        return self.drive_type == .ATAPI;
    }

    pub fn isATA(self: DriveInfo) bool {
        return self.drive_type == .ATA;
    }
};
