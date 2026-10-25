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

pub const Status = packed struct {
    err: bool,
    idx: bool,
    corrected: bool,
    drq: bool,
    seek_complete: bool,
    write_fault: bool,
    ready: bool,
    busy: bool,
};

pub const DeviceRegister = packed struct(u8) {
    lba_high: u4 = 0,
    dev: enum(u1) { Master = 0, Slave = 1 } = .Master,
    _always1: u1 = 1,
    addressing: enum(u1) { CHS = 0, LBA = 1 } = .CHS,
    _always1b: u1 = 1,

    pub fn ataLBA28(position: @import("channel.zig").DrivePosition, lba: u32) DeviceRegister {
        return .{
            .lba_high = @truncate(lba >> 24),
            .dev = if (position == .Master) .Master else .Slave,
            .addressing = .LBA,
        };
    }

    pub fn select(position: @import("channel.zig").DrivePosition) DeviceRegister {
        return .{
            .dev = if (position == .Master) .Master else .Slave,
        };
    }
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
    model: [40]u8,
    capacity: Capacity,
    removable: bool,

    pub fn isATAPI(self: DriveInfo) bool {
        return self.drive_type == .ATAPI;
    }

    pub fn isATA(self: DriveInfo) bool {
        return self.drive_type == .ATA;
    }
};
