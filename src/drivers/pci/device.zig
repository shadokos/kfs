const pci = @import("pci.zig");
const logger = @import("std").log.scoped(.pci_device);

bus: u8,
device: u8,
function: u8,
vendor_id: u16,
device_id: u16,
class_code: pci.PCIClass,
subclass: u8,
prog_if: u8,
revision: u8,
header_type: u8,
bars: [6]u32, // Base Address Registers
irq_line: u8,
irq_pin: u8,

const Self = @This();

/// Get PCI configuration address for this device
pub fn getAddress(self: *const Self) u32 {
    return (@as(u32, self.bus) << 16) |
        (@as(u32, self.device) << 11) |
        (@as(u32, self.function) << 8);
}

/// Check if this device is an IDE controller
pub fn isIDEController(self: *const Self) bool {
    return self.class_code == .MassStorage and self.subclass == 0x01;
}

/// Check if this device is a SATA controller
pub fn isSATAController(self: *const Self) bool {
    return self.class_code == .MassStorage and self.subclass == 0x06;
}

/// Get IDE interface type for this controller
pub fn getIDEInterface(self: *const Self) ?pci.IDEInterface {
    if (!self.isIDEController()) return null;
    return pci.IDEInterface.fromU8(self.prog_if);
}

/// Decode Base Address Register information
pub fn decodeBAR(self: *const Self, bar_index: u8) ?pci.BARInfo {
    if (bar_index >= 6) return null;
    const bar = self.bars[bar_index];

    if (bar == 0) return null;

    if ((bar & 0x1) != 0) {
        // I/O BAR
        return pci.BARInfo{
            .bar_type = .IO,
            .address = bar & 0xFFFFFFFC,
            .size = 0, // To be calculated separately
            .prefetchable = false,
        };
    } else {
        // Memory BAR
        const mem_type = (bar >> 1) & 0x3;
        const prefetchable = (bar & 0x8) != 0;

        return pci.BARInfo{
            .bar_type = if (mem_type == 0) .Memory32 else .Memory64,
            .address = bar & 0xFFFFFFF0,
            .size = 0, // To be calculated separately
            .prefetchable = prefetchable,
        };
    }
}

/// Enable device for I/O and memory access
pub fn enableDevice(self: *const Self) void {
    // Read the command register (offset 0x04)
    var command = pci.readConfig16(self.bus, self.device, self.function, 0x04);

    // Enable I/O and memory access
    command |= 0x01; // I/O Space Enable
    command |= 0x02; // Memory Space Enable
    command |= 0x04; // Bus Master Enable (for DMA)

    // Write the updated command back to the device
    pci.writeConfig16(self.bus, self.device, self.function, 0x04, command);

    logger.debug("{}:{}.{} (0x{x:0>4}) {s} enabled", .{
        self.bus,
        self.device,
        self.function,
        self.device_id,
        @tagName(self.class_code),
    });
}

/// Print detailed device information (for debugging)
pub fn printDeviceInfo(self: *const Self, printFn: anytype) void {
    printFn("PCI Device Info:\n", .{});
    printFn(" - Bus: {}\n", .{self.bus});
    printFn(" - Device: {}\n", .{self.device});
    printFn(" - Function: {}\n", .{self.function});
    printFn(" - Vendor ID: 0x{X:0>4}\n", .{self.vendor_id});
    printFn(" - Device ID: 0x{X:0>4}\n", .{self.device_id});
    printFn(" - Class Code: {s}\n", .{@tagName(self.class_code)});
    printFn(" - Subclass: 0x{X:0>2}\n", .{self.subclass});
    printFn(" - Programming Interface: 0x{X:0>2}\n", .{self.prog_if});
    printFn(" - Revision: 0x{X:0>2}\n", .{self.revision});
    printFn(" - IRQ Line: {}\n", .{self.irq_line});
    printFn(" - IRQ Pin: {}\n", .{self.irq_pin});
    printFn(" - Header Type: 0x{X:0>2}\n", .{self.header_type});
    printFn(" - Multifunction: {}\n", .{(self.header_type & 0x80) != 0});

    if (self.header_type == 0) {
        printFn(" - Base Address Registers (BARs):\n", .{});
        for (0..6) |i| {
            const bar = self.decodeBAR(@truncate(i));
            if (bar) |info| {
                printFn("   - BAR{}: Type: {s}, Address: 0x{X:0>8}, Size: {} bytes, Prefetchable: {}\n", .{
                    i, @tagName(info.bar_type), info.address, info.size, info.prefetchable,
                });
            } else {
                printFn("   - BAR{}: Not used\n", .{i});
            }
        }
    }
}
