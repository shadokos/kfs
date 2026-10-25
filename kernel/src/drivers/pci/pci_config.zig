const std = @import("std");

// === PCI CONFIGURATION SPACE CONSTANTS ===
pub const CONFIG_SPACE_SIZE = 256;
pub const CONFIG_HEADER_SIZE = 64;
pub const CONFIG_DWORD_SIZE = 4;
pub const CONFIG_DWORD_COUNT = 16; // 64 bytes / 4 bytes per dword

// === REGISTER OFFSETS ===
pub const OFFSET_VENDOR_ID = 0x00;
pub const OFFSET_DEVICE_ID = 0x02;
pub const OFFSET_COMMAND = 0x04;
pub const OFFSET_STATUS = 0x06;
pub const OFFSET_REVISION_ID = 0x08;
pub const OFFSET_PROG_IF = 0x09;
pub const OFFSET_SUBCLASS = 0x0A;
pub const OFFSET_CLASS_CODE = 0x0B;
pub const OFFSET_CACHE_LINE_SIZE = 0x0C;
pub const OFFSET_LATENCY_TIMER = 0x0D;
pub const OFFSET_HEADER_TYPE = 0x0E;
pub const OFFSET_BIST = 0x0F;
pub const OFFSET_BAR0 = 0x10;
pub const OFFSET_BAR1 = 0x14;
pub const OFFSET_BAR2 = 0x18;
pub const OFFSET_BAR3 = 0x1C;
pub const OFFSET_BAR4 = 0x20;
pub const OFFSET_BAR5 = 0x24;
pub const OFFSET_INTERRUPT_LINE = 0x3C;
pub const OFFSET_INTERRUPT_PIN = 0x3D;

// === BIT MASKS AND FLAGS ===
pub const BAR_IO_SPACE_BIT = 0x1;
pub const BAR_IO_SPACE_MASK = 0x1;
pub const BAR_MEMORY_TYPE_MASK = 0x6;
pub const BAR_PREFETCHABLE_BIT = 0x8;
pub const BAR_MEMORY_ADDRESS_MASK_32 = 0xFFFFFFF0;
pub const BAR_IO_ADDRESS_MASK = 0xFFFFFFFC;
pub const BAR_ADDRESS_ALIGNMENT_IO = 0x04;
pub const BAR_ADDRESS_ALIGNMENT_MEMORY = 0x10;

pub const REGISTER_OFFSET_MASK = 0xFC;

pub const MULTIFUNCTION_DEVICE_BIT = 0x80;
pub const HEADER_TYPE_MASK = 0x7F;

pub const COMMAND_IO_SPACE_ENABLE = 0x0001;
pub const COMMAND_MEMORY_SPACE_ENABLE = 0x0002;
pub const COMMAND_BUS_MASTER_ENABLE = 0x0004;
pub const COMMAND_INTERRUPT_DISABLE = 0x0400;

// === PCI ENUMERATION LIMITS ===
pub const MAX_BUSES = 256;
pub const MAX_DEVICES_PER_BUS = 32;
pub const MAX_FUNCTIONS_PER_DEVICE = 8;
pub const MAX_BARS = 6;

// === SPECIAL VALUES ===
pub const VENDOR_ID_INVALID = 0xFFFF;
pub const DEVICE_NOT_PRESENT = 0xFFFF;

/// PCI device class codes
/// Reference: https://sigops.acm.illinois.edu/old/roll_your_own/7.c.1.html
pub const PCIClass = enum(u8) {
    PrePCI2 = 0x00,
    MassStorage = 0x01,
    NetworkController = 0x02,
    DisplayController = 0x03,
    MultimediaDevice = 0x04,
    MemoryController = 0x05,
    BridgeDevice = 0x06,
    SimpleCommunicationController = 0x07,
    BaseSystemPeripheral = 0x08,
    InputDevice = 0x09,
    DockingStation = 0x0A,
    Processorts = 0x0B,
    SerialBusController = 0x0C,
    Misc = 0xFF,

    pub fn fromU8(value: u8) PCIClass {
        return @enumFromInt(value);
    }
};

/// IDE controller programming interface (subclass 0x01)
/// TODO: implement more classes and subclasses
pub const IDEInterface = enum(u8) {
    ISACompatibility = 0x00,
    PCINativeMode = 0x05,
    ISACompatibilityModePrimary = 0x0A,
    ISACompatibilityModeSecondary = 0x0F,
    PCINativeModeWithBusMaster = 0x80,
    PCINativeModeBothChannels = 0x85,
    PCINativeModeBusMasterBoth = 0x8A,
    FullPCINativeMode = 0x8F,

    pub fn fromU8(value: u8) IDEInterface {
        return @enumFromInt(value);
    }

    /// Check if this interface supports bus master DMA
    pub fn supportsBusMaster(self: IDEInterface) bool {
        return (@intFromEnum(self) & 0x80) != 0;
    }

    /// Check if this interface uses PCI native mode
    pub fn isPCINative(self: IDEInterface) bool {
        return (@intFromEnum(self) & 0x05) != 0;
    }
};

pub const PCIConfigHeader = packed struct {
    // Offset 0x00
    vendor_id: u16,
    device_id: u16,

    // Offset 0x04
    command: CommandRegister,
    status: StatusRegister,

    // Offset 0x08
    revision_id: u8,
    prog_if: u8,
    subclass: u8,
    class_code: u8,

    // Offset 0x0C
    cache_line_size: u8,
    latency_timer: u8,
    header_type: HeaderType,
    bist: u8,

    // Offset 0x10 - 0x24: Base Address Registers
    bar0: u32,
    bar1: u32,
    bar2: u32,
    bar3: u32,
    bar4: u32,
    bar5: u32,

    // Offset 0x28
    cardbus_cis_pointer: u32,

    // Offset 0x2C
    subsystem_vendor_id: u16,
    subsystem_id: u16,

    // Offset 0x30
    expansion_rom_base: u32,

    // Offset 0x34
    capabilities_pointer: u8,
    _reserved1: u24,

    // Offset 0x38
    _reserved2: u32,

    // Offset 0x3C
    interrupt_line: u8,
    interrupt_pin: u8,
    min_grant: u8,
    max_latency: u8,

    comptime {
        // Check that the structure is exactly 64 bytes (512 bits for the standard header)
        std.debug.assert(@sizeOf(@This()) == 64);
    }
};

/// Command Register (Offset 0x04)
pub const CommandRegister = packed struct(u16) {
    io_space: bool, // bit 0: I/O Space Enable
    memory_space: bool, // bit 1: Memory Space Enable
    bus_master: bool, // bit 2: Bus Master Enable
    special_cycles: bool, // bit 3: Special Cycles Enable
    memory_write_invalidate: bool, // bit 4
    vga_palette_snoop: bool, // bit 5
    parity_error_response: bool, // bit 6
    _reserved1: u1, // bit 7
    serr_enable: bool, // bit 8
    fast_b2b_enable: bool, // bit 9
    interrupt_disable: bool, // bit 10
    _reserved2: u5, // bits 11-15

    pub fn enable() CommandRegister {
        return .{
            .io_space = true,
            .memory_space = false,
            .bus_master = true,
            .special_cycles = false,
            .memory_write_invalidate = false,
            .vga_palette_snoop = false,
            .parity_error_response = false,
            ._reserved1 = 0,
            .serr_enable = false,
            .fast_b2b_enable = false,
            .interrupt_disable = false,
            ._reserved2 = 0,
        };
    }
};

/// Status Register (Offset 0x06)
pub const StatusRegister = packed struct(u16) {
    _reserved1: u3,
    interrupt_status: bool, // bit 3
    capabilities_list: bool, // bit 4
    capable_66mhz: bool, // bit 5
    _reserved2: u1,
    fast_b2b_capable: bool, // bit 7
    master_data_parity_error: bool, // bit 8
    devsel_timing: u2, // bits 9-10
    signaled_target_abort: bool, // bit 11
    received_target_abort: bool, // bit 12
    received_master_abort: bool, // bit 13
    signaled_system_error: bool, // bit 14
    detected_parity_error: bool, // bit 15
};

/// Header Type Register (Offset 0x0E)
pub const HeaderType = packed struct(u8) {
    layout: HeaderLayout, // bits 0-6
    multi_function: bool, // bit 7

    pub const HeaderLayout = enum(u7) {
        general_device = 0x00,
        pci_to_pci_bridge = 0x01,
        cardbus_bridge = 0x02,
        _,
    };
};

/// Base Address Register (BAR)
pub const BAR = struct {
    // Decoded information from a BAR
    pub const Info = struct {
        bar_type: Type,
        address: u32,
        size: u32 = 0, // To be calculated separately via getBARSize
        prefetchable: bool,

        pub const Type = enum {
            IO,
            Memory32,
            Memory64,
        };
    };

    /// For I/O BAR
    pub const IO = packed struct(u32) {
        is_io: u1, // bit 0: always 1 for I/O
        _reserved: u1,
        address: u30, // bits 2-31: address aligned on 4 bytes

        pub fn getAddress(self: IO) u32 {
            return @as(u32, self.address) << 2;
        }
    };

    /// For Memory BAR
    pub const Memory = packed struct(u32) {
        is_io: u1, // bit 0: always 0 for Memory
        mem_type: MemType, // bits 1-2
        prefetchable: bool, // bit 3
        address: u28, // bits 4-31: address aligned on 16 bytes

        pub const MemType = enum(u2) {
            bits_32 = 0b00,
            below_1mb = 0b01, // obsolete
            _,
        };

        pub fn getAddress(self: Memory) u32 {
            return @as(u32, self.address) << 4;
        }
    };

    /// Parse raw BAR
    pub fn parse(raw: u32) union(enum) { io: IO, memory: Memory } {
        if ((raw & 0x1) != 0) {
            return .{ .io = @bitCast(raw) };
        } else {
            return .{ .memory = @bitCast(raw) };
        }
    }

    /// Decode raw BAR into usable information
    pub fn decode(raw: u32) ?Info {
        if (raw == 0 or raw == 0xffffffff) return null;

        const parsed = parse(raw);
        return switch (parsed) {
            .io => |io_bar| Info{
                .bar_type = .IO,
                .address = io_bar.getAddress(),
                .prefetchable = false,
            },
            .memory => |mem_bar| Info{
                .bar_type = .Memory32,
                .address = mem_bar.getAddress(),
                .prefetchable = mem_bar.prefetchable,
            },
        };
    }
};
