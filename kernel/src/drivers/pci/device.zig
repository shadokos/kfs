const std = @import("std");
const pci = @import("pci.zig");
const pci_config = @import("pci_config.zig");
const logger = std.log.scoped(.pci_device);

const HeaderType = pci_config.HeaderType;

pub const BusId = u8;
pub const DeviceId = u5;
pub const FunctionId = u3;

bus: BusId,
device: DeviceId,
function: FunctionId,
vendor_id: u16,
device_id: u16,
class_code: pci_config.PCIClass,
subclass: u8,
prog_if: u8,
revision: u8,
header_type: HeaderType,
bars: [pci_config.MAX_BARS]u32, // Base Address Registers
irq_line: u8,
irq_pin: u8,

const Self = @This();

// === PCI Subclass Constants ===
const SUBCLASS_IDE: u8 = 0x01;
const SUBCLASS_SATA: u8 = 0x06;

/// Get PCI configuration address for this device
pub fn getAddress(self: *const Self) u32 {
    return @bitCast(pci.ConfigAddress.make(
        self.bus,
        self.device,
        self.function,
        0,
    ));
}

/// Check if this device is an IDE controller
pub fn isIDEController(self: *const Self) bool {
    return self.class_code == .MassStorage and self.subclass == SUBCLASS_IDE;
}

/// Check if this device is a SATA controller
pub fn isSATAController(self: *const Self) bool {
    return self.class_code == .MassStorage and self.subclass == SUBCLASS_SATA;
}

/// Get IDE interface type for this controller
pub fn getIDEInterface(self: *const Self) ?pci_config.IDEInterface {
    if (!self.isIDEController()) return null;
    return pci_config.IDEInterface.fromU8(self.prog_if);
}

pub fn decodeBAR(self: *const Self, bar_index: u8) ?pci_config.BAR.Info {
    if (bar_index >= pci_config.MAX_BARS) return null;
    return pci_config.BAR.decode(self.bars[bar_index]);
}

/// Enable device for I/O and memory access
pub fn enableDevice(self: *const Self) void {
    // Read the command register
    var command = pci.readConfig(u16, self.bus, self.device, self.function, pci_config.OFFSET_COMMAND);
    command |= @bitCast(pci_config.CommandRegister.enable());

    // Write the updated command back to the device
    pci.writeConfig(u16, self.bus, self.device, self.function, pci_config.OFFSET_COMMAND, command);

    logger.debug("{}:{}.{} (0x{x:0>4}) {s} enabled", .{
        self.bus,
        self.device,
        self.function,
        self.device_id,
        @tagName(self.class_code),
    });
}

/// Print detailed device information (for debugging)
pub fn printInfo(self: *const Self, writer: std.io.AnyWriter) void {
    _ = std.fmt.format(writer, "PCI Device Info:\n", .{}) catch {};
    _ = std.fmt.format(writer, " - Bus: {}\n", .{self.bus}) catch {};
    _ = std.fmt.format(writer, " - Device: {}\n", .{self.device}) catch {};
    _ = std.fmt.format(writer, " - Function: {}\n", .{self.function}) catch {};
    _ = std.fmt.format(writer, " - Vendor ID: 0x{X:0>4}\n", .{self.vendor_id}) catch {};
    _ = std.fmt.format(writer, " - Device ID: 0x{X:0>4}\n", .{self.device_id}) catch {};
    _ = std.fmt.format(writer, " - Class Code: {s}\n", .{@tagName(self.class_code)}) catch {};
    _ = std.fmt.format(writer, " - Subclass: 0x{X:0>2}\n", .{self.subclass}) catch {};
    _ = std.fmt.format(writer, " - Programming Interface: 0x{X:0>2}\n", .{self.prog_if}) catch {};
    _ = std.fmt.format(writer, " - Revision: 0x{X:0>2}\n", .{self.revision}) catch {};
    _ = std.fmt.format(writer, " - IRQ Line: {}\n", .{self.irq_line}) catch {};
    _ = std.fmt.format(writer, " - IRQ Pin: {}\n", .{self.irq_pin}) catch {};
    _ = std.fmt.format(writer, " - Header Type: 0x{X:0>2}\n", .{@as(u8, @bitCast(self.header_type))}) catch {};
    _ = std.fmt.format(writer, " - Multifunction: {}\n", .{self.header_type.multi_function}) catch {};

    if (self.header_type.layout == .general_device) {
        _ = std.fmt.format(writer, " - Base Address Registers (BARs):\n", .{}) catch {};
        for (0..pci_config.MAX_BARS) |i| {
            const bar = self.decodeBAR(@intCast(i));
            if (bar) |info| {
                _ = std.fmt.format(
                    writer,
                    "   - BAR{}: Type: {s}, Address: 0x{X:0>8}, Size: {} bytes, Prefetchable: {}\n",
                    .{ i, @tagName(info.bar_type), info.address, info.size, info.prefetchable },
                ) catch {};
            } else {
                _ = std.fmt.format(writer, "   - BAR{}: Not used\n", .{i}) catch {};
            }
        }
    }
}
