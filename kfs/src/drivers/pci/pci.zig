const std = @import("std");
const cpu = @import("../../cpu.zig");
const pci_config = @import("pci_config.zig");
const logger = std.log.scoped(.driver_pci);
const PCIDeviceList = std.ArrayListAligned(PCIDevice, .@"4");
const Allocator = std.mem.Allocator;

const allocator = @import("../../memory.zig").smallAlloc.allocator();
var devices: PCIDeviceList = .empty;

// === PUBLIC CONSTANTS ===
pub const PCI_CONFIG_ADDRESS: u16 = 0xCF8;
pub const PCI_CONFIG_DATA: u16 = 0xCFC;

// === PUBLIC TYPES ===
pub const PCIDevice = @import("device.zig");
const BusId = PCIDevice.BusId;
const DeviceId = PCIDevice.DeviceId;
const FunctionId = PCIDevice.FunctionId;

pub const PCIError = error{
    DeviceNotFound,
    InvalidFunction,
    InvalidBAR,
    ConfigError,
    OutOfMemory,
};

/// Adresse de configuration PCI (packed struct)
pub const ConfigAddress = packed struct(u32) {
    register_offset: u8, // bits 0-7 (bits 0-1 always 0)
    function: FunctionId, // bits 8-10
    device: DeviceId, // bits 11-15
    bus: BusId, // bits 16-23
    _reserved: u7 = 0, // bits 24-30
    enable: bool = true, // bit 31

    pub fn make(bus: BusId, device: DeviceId, function: FunctionId, offset: u8) ConfigAddress {
        return .{
            .register_offset = offset & pci_config.REGISTER_OFFSET_MASK,
            .function = function,
            .device = device,
            .bus = bus,
        };
    }

    pub fn toU32(self: ConfigAddress) u32 {
        return @bitCast(self);
    }
};

const PCIConfigHeader = pci_config.PCIConfigHeader;
const PCIClass = pci_config.PCIClass;
const CommandRegister = pci_config.CommandRegister;
const StatusRegister = pci_config.StatusRegister;
const HeaderType = pci_config.HeaderType;
const BAR = pci_config.BAR;

const IDEInterface = pci_config.IDEInterface;

// === PRIVATE METHODS ===

/// Scan all PCI buses, devices, and functions
fn scanAllDevices() !void {
    for (0..pci_config.MAX_BUSES) |bus| {
        try scanBus(@intCast(bus));
    }
}

/// Scan all devices on a specific bus
fn scanBus(bus: BusId) !void {
    for (0..pci_config.MAX_DEVICES_PER_BUS) |device| {
        try scanDevice(bus, @intCast(device));
    }
}

/// Scan a specific device and its functions
fn scanDevice(bus: BusId, device: DeviceId) !void {
    // Function 0 is always present, but we need to check if the device exists
    const vendor_id = readConfig(u16, bus, device, 0, pci_config.OFFSET_VENDOR_ID);
    if (vendor_id == pci_config.DEVICE_NOT_PRESENT) return; // Device not present

    const header_type = readConfig(u8, bus, device, 0, pci_config.OFFSET_HEADER_TYPE);
    const is_multifunction = (header_type & pci_config.MULTIFUNCTION_DEVICE_BIT) != 0;

    // Function 0 is always present, so we scan it first
    try scanFunction(bus, device, 0);

    // If the device is multifunction, we scan the other functions
    if (is_multifunction) {
        for (1..pci_config.MAX_FUNCTIONS_PER_DEVICE) |func| {
            const func_vendor = readConfig(u16, bus, device, @intCast(func), pci_config.OFFSET_VENDOR_ID);
            if (func_vendor != pci_config.DEVICE_NOT_PRESENT) {
                try scanFunction(bus, device, @intCast(func));
            }
        }
    }
}

/// Scan and register a specific PCI function
fn scanFunction(bus: BusId, device: DeviceId, function: FunctionId) !void {
    const header = readConfigHeader(bus, device, function);

    if (header.vendor_id == pci_config.DEVICE_NOT_PRESENT) return;

    // Read Base Address Registers (BARs), only for header type 0 (general device)
    var bars: [pci_config.MAX_BARS]u32 = .{0} ** pci_config.MAX_BARS;
    if (header.header_type.layout == .general_device) {
        bars[0] = header.bar0;
        bars[1] = header.bar1;
        bars[2] = header.bar2;
        bars[3] = header.bar3;
        bars[4] = header.bar4;
        bars[5] = header.bar5;
    }

    const pci_device = PCIDevice{
        .bus = bus,
        .device = device,
        .function = function,
        .vendor_id = header.vendor_id,
        .device_id = header.device_id,
        .class_code = PCIClass.fromU8(header.class_code),
        .subclass = header.subclass,
        .prog_if = header.prog_if,
        .revision = header.revision_id,
        .header_type = header.header_type,
        .bars = bars,
        .irq_line = header.interrupt_line,
        .irq_pin = header.interrupt_pin,
    };

    try devices.append(allocator, pci_device);

    logger.debug("PCI device (0x{X:0>4}): {s}(0x{X:0>2})", .{
        header.device_id,
        @tagName(pci_device.class_code),
        header.subclass,
    });
}

// === PUBLIC METHODS ===

/// Generic read from PCI configuration space
/// Supports u8, u16, and u32 types
pub fn readConfig(comptime T: type, bus: u8, device: u5, function: u3, offset: u8) T {
    comptime {
        if (T != u8 and T != u16 and T != u32) {
            @compileError("readConfig only supports u8, u16, or u32 types");
        }
    }

    const address = ConfigAddress.make(bus, device, function, offset);
    cpu.outl(PCI_CONFIG_ADDRESS, address.toU32());

    const data = cpu.inl(PCI_CONFIG_DATA);

    // Calculate shift based on type size and offset alignment
    const byte_offset = offset & 0x3;
    const shift: u5 = @intCast(byte_offset * 8);

    return @truncate(data >> shift);
}

/// Generic write to PCI configuration space
/// Supports u8, u16, and u32 types
pub fn writeConfig(comptime T: type, bus: u8, device: u5, function: u3, offset: u8, value: T) void {
    comptime {
        if (T != u8 and T != u16 and T != u32) {
            @compileError("writeConfig only supports u8, u16, or u32 types");
        }
    }

    const address = ConfigAddress.make(bus, device, function, offset);
    cpu.outl(PCI_CONFIG_ADDRESS, address.toU32());

    if (T == u32) {
        // For 32-bit writes, write directly
        cpu.outl(PCI_CONFIG_DATA, value);
    } else {
        // For 8-bit and 16-bit writes, read-modify-write
        const current = cpu.inl(PCI_CONFIG_DATA);
        const byte_offset = offset & 0x3;
        const shift: u5 = @intCast(byte_offset * 8);

        // Ensure we only modify the relevant bits
        const type_bits = @bitSizeOf(T);
        // Create a mask to clear the bits we want to write
        // e.g., for u8: type_bits = 8, mask = ~(0xFF << shift)
        const mask = ~(@as(u32, (@as(u32, 1) << type_bits) - 1) << shift);
        // Set the new value in the correct position
        const new_value = (current & mask) | (@as(u32, value) << shift);

        cpu.outl(PCI_CONFIG_DATA, new_value);
    }
}

/// Lire le header de configuration complet
pub fn readConfigHeader(bus: u8, device: u5, function: u3) PCIConfigHeader {
    var data: [pci_config.CONFIG_DWORD_COUNT]u32 = undefined;
    for (0..pci_config.CONFIG_DWORD_COUNT) |i| {
        data[i] = readConfig(u32, bus, device, function, @intCast(i * pci_config.CONFIG_DWORD_SIZE));
    }
    return @bitCast(data);
}

/// Enable a PCI device (I/O, Memory, Bus Master)
pub fn enableDevice(bus: u8, device: u5, function: u3) void {
    const cmd = CommandRegister.enable();
    writeConfig(u16, bus, device, function, pci_config.OFFSET_COMMAND, @bitCast(cmd));
}

/// Find all devices matching a specific class and optionally subclass
pub fn findDevicesByClass(class: PCIClass, subclass: ?u8) ?[]PCIDevice {
    var result: PCIDeviceList = .empty;
    defer result.deinit(allocator);

    for (devices.items) |device| {
        if (device.class_code == class) {
            if (subclass == null or device.subclass == subclass.?) {
                logger.debug("Found device {}:{}.{} - Vendor: 0x{X:0>4}, Device: 0x{X:0>4}", .{
                    device.bus, device.device, device.function, device.vendor_id, device.device_id,
                });
                result.append(allocator, device) catch continue;
            }
        }
    }

    return result.toOwnedSlice(allocator) catch null;
}

/// Find all IDE controllers
pub fn findIDEControllers() ?[]PCIDevice {
    return findDevicesByClass(.MassStorage, 0x01);
}

/// Find all SATA controllers
pub fn findSATAControllers() ?[]PCIDevice {
    return findDevicesByClass(.MassStorage, 0x06);
}

/// Find device by device ID
pub fn get_device(bus: u8, device: u8, func: u8) ?PCIDevice {
    for (devices.items) |dev| {
        if (dev.bus == bus and dev.device == device and dev.function == func)
            return dev;
    }
    return null;
}

pub fn get_devices() []PCIDevice {
    return devices.items;
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
