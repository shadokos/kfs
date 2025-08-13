const std = @import("std");
const cpu = @import("../../cpu.zig");
const logger = std.log.scoped(.driver_pci);
const PCIDeviceList = std.ArrayListAligned(PCIDevice, 4);
const Allocator = std.mem.Allocator;

const allocator = @import("../../memory.zig").smallAlloc.allocator();
var devices: PCIDeviceList = PCIDeviceList.init(allocator);

// === PUBLIC TYPES ===

pub const PCIDevice = @import("device.zig");

pub const PCIError = error{
    DeviceNotFound,
    InvalidFunction,
    InvalidBAR,
    ConfigError,
    OutOfMemory,
};

pub const PCI_CONFIG_ADDRESS: u16 = 0xCF8;
pub const PCI_CONFIG_DATA: u16 = 0xCFC;

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

/// Base Address Register information
pub const BARInfo = struct {
    bar_type: BARType,
    address: u32,
    size: u32,
    prefetchable: bool,

    pub const BARType = enum {
        IO,
        Memory32,
        Memory64,
    };
};

// === PRIVATE METHODS ===

/// Scan all PCI buses, devices, and functions
fn scanAllDevices() !void {
    for (0..256) |bus| {
        try scanBus(@truncate(bus));
    }
}

/// Scan all devices on a specific bus
fn scanBus(bus: u8) !void {
    for (0..32) |device| {
        try scanDevice(bus, @truncate(device));
    }
}

/// Scan a specific device and its functions
fn scanDevice(bus: u8, device: u8) !void {
    // Function 0 is always present, but we need to check if the device exists
    const vendor_id = readConfig16(bus, device, 0, 0x00);
    if (vendor_id == 0xFFFF) return; // Device not present

    const header_type = readConfig8(bus, device, 0, 0x0E);
    const is_multifunction = (header_type & 0x80) != 0;

    // Function 0 is always present, so we scan it first
    try scanFunction(bus, device, 0);

    // If the device is multifunction, we scan the other functions
    if (is_multifunction) {
        for (1..8) |func| {
            const func_vendor = readConfig16(bus, device, @truncate(func), 0x00);
            if (func_vendor != 0xFFFF) {
                try scanFunction(bus, device, @truncate(func));
            }
        }
    }
}

/// Scan and register a specific PCI function
fn scanFunction(bus: u8, device: u8, function: u8) !void {
    const vendor_id = readConfig16(bus, device, function, 0x00);
    if (vendor_id == 0xFFFF) return;

    const device_id = readConfig16(bus, device, function, 0x02);
    const class_subclass = readConfig16(bus, device, function, 0x0A);
    const class_code = PCIClass.fromU8(@truncate(class_subclass >> 8));
    const subclass = @as(u8, @truncate(class_subclass));
    const prog_if = readConfig8(bus, device, function, 0x09);
    const revision = readConfig8(bus, device, function, 0x08);
    const header_type = readConfig8(bus, device, function, 0x0E) & 0x7F;

    // Read Base Address Registers (BARs), only for header type 0
    var bars: [6]u32 = .{0} ** 6;
    if (header_type == 0) {
        for (0..6) |i| {
            bars[i] = readConfig32(bus, device, function, 0x10 + @as(u8, @truncate(i * 4)));
        }
    }

    // Read IRQ line and pin
    const irq_line = readConfig8(bus, device, function, 0x3C);
    const irq_pin = readConfig8(bus, device, function, 0x3D);

    const pci_device = PCIDevice{
        .bus = bus,
        .device = device,
        .function = function,
        .vendor_id = vendor_id,
        .device_id = device_id,
        .class_code = class_code,
        .subclass = subclass,
        .prog_if = prog_if,
        .revision = revision,
        .header_type = header_type,
        .bars = bars,
        .irq_line = irq_line,
        .irq_pin = irq_pin,
    };

    try devices.append(pci_device);

    //TODO: Maybe display device infos in a better way
    logger.debug("PCI device (0x{X:0>4}): {s}(0x{X:0>2})", .{ device_id, @tagName(class_code), subclass });
}

// === PUBLIC METHODS ===

/// Create PCI configuration address for register access
pub fn makeConfigAddress(bus: u8, device: u8, function: u8, offset: u8) u32 {
    return (1 << 31) | // Enable bit
        (@as(u32, bus) << 16) |
        (@as(u32, device & 0x1F) << 11) |
        (@as(u32, function & 0x07) << 8) |
        (@as(u32, offset & 0xFC));
}

/// Read 8-bit value from PCI configuration space
pub fn readConfig8(bus: u8, device: u8, function: u8, offset: u8) u8 {
    const address = makeConfigAddress(bus, device, function, offset);
    cpu.outl(PCI_CONFIG_ADDRESS, address);
    const shift = (offset & 3) * 8;
    return @truncate(cpu.inl(PCI_CONFIG_DATA) >> @truncate(shift));
}

/// Read 16-bit value from PCI configuration space
pub fn readConfig16(bus: u8, device: u8, function: u8, offset: u8) u16 {
    const address = makeConfigAddress(bus, device, function, offset);
    cpu.outl(PCI_CONFIG_ADDRESS, address);
    const shift = (offset & 2) * 8;
    return @truncate(cpu.inl(PCI_CONFIG_DATA) >> @truncate(shift));
}

/// Read 32-bit value from PCI configuration space
pub fn readConfig32(bus: u8, device: u8, function: u8, offset: u8) u32 {
    const address = makeConfigAddress(bus, device, function, offset & 0xFC);
    cpu.outl(PCI_CONFIG_ADDRESS, address);
    return cpu.inl(PCI_CONFIG_DATA);
}

/// Write 8-bit value to PCI configuration space
pub fn writeConfig8(bus: u8, device: u8, function: u8, offset: u8, value: u8) void {
    const address = makeConfigAddress(bus, device, function, offset);
    cpu.outl(PCI_CONFIG_ADDRESS, address);

    const current = cpu.inl(PCI_CONFIG_DATA);
    const shift = @as(u5, @truncate((offset & 3) * 8));
    const mask = ~(@as(u32, 0xFF) << shift);
    const new_value = (current & mask) | (@as(u32, value) << shift);

    cpu.outl(PCI_CONFIG_DATA, new_value);
}

/// Write 16-bit value to PCI configuration space
pub fn writeConfig16(bus: u8, device: u8, function: u8, offset: u8, value: u16) void {
    const address = makeConfigAddress(bus, device, function, offset);
    cpu.outl(PCI_CONFIG_ADDRESS, address);

    const current = cpu.inl(PCI_CONFIG_DATA);
    const shift = @as(u5, @truncate((offset & 2) * 8));
    const mask = ~(@as(u32, 0xFFFF) << shift);
    const new_value = (current & mask) | (@as(u32, value) << shift);

    cpu.outl(PCI_CONFIG_DATA, new_value);
}

/// Write 32-bit value to PCI configuration space
pub fn writeConfig32(bus: u8, device: u8, function: u8, offset: u8, value: u32) void {
    const address = makeConfigAddress(bus, device, function, offset & 0xFC);
    cpu.outl(PCI_CONFIG_ADDRESS, address);
    cpu.outl(PCI_CONFIG_DATA, value);
}

/// Find all devices matching a specific class and optionally subclass
pub fn findDevicesByClass(class: PCIClass, subclass: ?u8) ?[]PCIDevice {
    var result = PCIDeviceList.init(allocator);
    defer result.deinit();

    for (devices.items) |device| {
        if (device.class_code == class) {
            if (subclass == null or device.subclass == subclass.?) {
                logger.debug("Found device {}:{}.{} - Vendor: 0x{X:0>4}, Device: 0x{X:0>4}", .{
                    device.bus, device.device, device.function, device.vendor_id, device.device_id,
                });
                result.append(device) catch continue;
            }
        }
    }

    return result.toOwnedSlice() catch null;
}

/// Find all IDE controllers
pub fn findIDEControllers() ?[]PCIDevice {
    return findDevicesByClass(.MassStorage, 0x01);
}

/// Find all SATA controllers
pub fn findSATAControllers() ?[]PCIDevice {
    return findDevicesByClass(.MassStorage, 0x06);
}

/// Get the size of a Base Address Register
pub fn getBARSize(device: *PCIDevice, bar_index: u8) !u32 {
    if (bar_index >= 6) return PCIError.InvalidBAR;

    const offset = 0x10 + bar_index * 4;

    // Save the original value of the BAR
    const original = readConfig32(device.bus, device.device, device.function, offset);

    // Write 0xFFFFFFFF to the BAR to get the size
    writeConfig32(device.bus, device.device, device.function, offset, 0xFFFFFFFF);

    // Get the response from the device
    const response = readConfig32(device.bus, device.device, device.function, offset);

    // Restore the original value of the BAR
    writeConfig32(device.bus, device.device, device.function, offset, original);

    // If the response is 0, the BAR is not used
    if (response == 0) return 0;

    // Calculate the size of the BAR
    var size: u32 = 1;
    var temp = response;

    if ((original & 0x1) != 0) {
        // I/O BAR - ignore the 2 least significant bits
        temp &= 0xFFFFFFFC;
    } else {
        // Memory BAR - ignore the 4 least significant bits
        temp &= 0xFFFFFFF0;
    }

    // Calculate the size by shifting until the least significant bit is set
    while ((temp & 1) == 0 and temp != 0) {
        size <<= 1;
        temp >>= 1;
    }

    return size;
}

/// Find device by device ID
pub fn get_device(device_id: u16) ?PCIDevice {
    for (devices.items) |dev| {
        if (dev.device_id == device_id)
            return dev;
    }
    return null;
}

/// Initialize PCI driver and scan for devices
pub fn init() !void {
    try scanAllDevices();
    logger.info("PCI driver initialized, {} devices found", .{devices.items.len});
}

/// Clean up PCI driver resources
pub fn deinit() void {
    devices.deinit();
}
