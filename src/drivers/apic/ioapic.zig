// src/drivers/apic/ioapic.zig
const paging = @import("../../memory/paging.zig");
const memory = @import("../../memory.zig");
const logger = @import("ft").log.scoped(.ioapic);
const lapic = @import("lapic.zig");

// IOAPIC register offsets
const IOREGSEL = 0x00; // Register select
const IOWIN = 0x10; // Data window

// IOAPIC registers (accessed via IOREGSEL/IOWIN)
const IOAPICID = 0x00;
const IOAPICVER = 0x01;
const IOAPICARB = 0x02;
const IOREDTBL = 0x10; // Redirection table base

// Default IOAPIC physical address
const IOAPIC_DEFAULT_BASE: u32 = 0xFEC00000;

// Redirection Entry structure
pub const RedirectionEntry = packed struct(u64) {
    vector: u8, // Interrupt vector
    delivery_mode: u3, // 000: Fixed, 001: Lowest Priority, 010: SMI, 100: NMI, 101: INIT, 111: ExtINT
    dest_mode: bool, // 0: Physical, 1: Logical
    delivery_status: bool, // 0: Idle, 1: Send Pending
    pin_polarity: bool, // 0: Active High, 1: Active Low
    remote_irr: bool, // Remote IRR (level triggered only)
    trigger_mode: bool, // 0: Edge, 1: Level
    mask: bool, // 0: Enabled, 1: Masked
    reserved: u39,
    destination: u8, // Destination APIC ID
};

// IRQ mapping structure
pub const IrqMapping = struct {
    global_irq: u32,
    source_irq: u8,
    active_low: bool,
    level_triggered: bool,
};

// IOAPIC structure
pub const IOApic = struct {
    id: u8,
    phys_addr: u32,
    virt_addr: [*]volatile u32,
    gsi_base: u32,
    max_entries: u8,

    // Read IOAPIC register
    pub fn read_reg(self: *const IOApic, reg: u8) u32 {
        self.virt_addr[IOREGSEL / 4] = reg;
        return self.virt_addr[IOWIN / 4];
    }

    // Write IOAPIC register
    pub fn write_reg(self: *IOApic, reg: u8, value: u32) void {
        self.virt_addr[IOREGSEL / 4] = reg;
        self.virt_addr[IOWIN / 4] = value;
    }

    // Read redirection entry
    pub fn read_redirection_entry(self: *const IOApic, index: u8) RedirectionEntry {
        const low = self.read_reg(IOREDTBL + 2 * index);
        const high = self.read_reg(IOREDTBL + 2 * index + 1);
        return @bitCast(@as(u64, high) << 32 | low);
    }

    // Write redirection entry
    pub fn write_redirection_entry(self: *IOApic, index: u8, entry: RedirectionEntry) void {
        const value: u64 = @bitCast(entry);
        self.write_reg(IOREDTBL + 2 * index, @truncate(value));
        self.write_reg(IOREDTBL + 2 * index + 1, @truncate(value >> 32));
    }

    // Mask an IRQ
    pub fn mask_irq(self: *IOApic, irq: u8) void {
        var entry = self.read_redirection_entry(irq);
        entry.mask = true;
        self.write_redirection_entry(irq, entry);
    }

    // Unmask an IRQ
    pub fn unmask_irq(self: *IOApic, irq: u8) void {
        var entry = self.read_redirection_entry(irq);
        entry.mask = false;
        self.write_redirection_entry(irq, entry);
    }
};

// Maximum number of IOAPICs supported
const MAX_IOAPICS = 8;

// Global IOAPIC state
var ioapics: [MAX_IOAPICS]IOApic = undefined;
var num_ioapics: u8 = 0;

// IRQ override table (from ACPI MADT)
var irq_overrides: [16]?IrqMapping = [_]?IrqMapping{null} ** 16;

// Register an IOAPIC
pub fn register_ioapic(id: u8, phys_addr: u32, gsi_base: u32) !void {
    if (num_ioapics >= MAX_IOAPICS) {
        return error.TooManyIOAPICs;
    }

    logger.debug("Registering IOAPIC {} at 0x{x}, GSI base {}", .{ id, phys_addr, gsi_base });

    // Map IOAPIC registers to virtual memory
    const virt_addr = try memory.map_mmio(phys_addr, 0x1000);

    var ioapic = &ioapics[num_ioapics];
    ioapic.* = .{
        .id = id,
        .phys_addr = phys_addr,
        .virt_addr = @ptrCast(@alignCast(virt_addr)),
        .gsi_base = gsi_base,
        .max_entries = 0,
    };

    // Read IOAPIC version to get max entries
    const version = ioapic.read_reg(IOAPICVER);
    ioapic.max_entries = @truncate((version >> 16) + 1);

    logger.info("IOAPIC {} initialized with {} entries", .{ id, ioapic.max_entries });

    num_ioapics += 1;
}

// Register an IRQ override (from ACPI)
pub fn register_irq_override(source_irq: u8, global_irq: u32, active_low: bool, level_triggered: bool) void {
    logger.debug("IRQ override: source {} -> GSI {}, active {s}, {s}", .{
        source_irq,
        global_irq,
        if (active_low) "low" else "high",
        if (level_triggered) "level" else "edge",
    });

    irq_overrides[source_irq] = .{
        .global_irq = global_irq,
        .source_irq = source_irq,
        .active_low = active_low,
        .level_triggered = level_triggered,
    };
}

// Find IOAPIC for a given GSI
pub fn find_ioapic_for_gsi(gsi: u32) ?*IOApic {
    for (ioapics[0..num_ioapics]) |*ioapic| {
        if (gsi >= ioapic.gsi_base and gsi < ioapic.gsi_base + ioapic.max_entries) {
            return ioapic;
        }
    }
    return null;
}

// Configure an IRQ
pub fn configure_irq(source_irq: u8, vector: u8, dest_apic_id: u8) !void {
    // Check for IRQ override
    const mapping = irq_overrides[source_irq] orelse IrqMapping{
        .global_irq = source_irq,
        .source_irq = source_irq,
        .active_low = false,
        .level_triggered = false,
    };

    // Find the IOAPIC that handles this GSI
    const ioapic = find_ioapic_for_gsi(mapping.global_irq) orelse {
        logger.err("No IOAPIC found for GSI {}", .{mapping.global_irq});
        return error.NoIOAPICForGSI;
    };

    const pin = @as(u8, @truncate(mapping.global_irq - ioapic.gsi_base));

    // Configure redirection entry
    const entry = RedirectionEntry{
        .vector = vector,
        .delivery_mode = 0, // Fixed
        .dest_mode = false, // Physical
        .delivery_status = false,
        .pin_polarity = mapping.active_low,
        .remote_irr = false,
        .trigger_mode = mapping.level_triggered,
        .mask = false, // Enable immediately
        .reserved = 0,
        .destination = dest_apic_id,
    };

    ioapic.write_redirection_entry(pin, entry);

    logger.debug("Configured IRQ {} (GSI {}) -> vector 0x{x} on CPU {}", .{
        source_irq,
        mapping.global_irq,
        vector,
        dest_apic_id,
    });
}

// Initialize all IOAPICs
pub fn init() !void {
    logger.debug("Initializing IOAPICs", .{});

    // Mask all interrupts on all IOAPICs
    for (ioapics[0..num_ioapics]) |*ioapic| {
        var i: u8 = 0;
        while (i < ioapic.max_entries) : (i += 1) {
            ioapic.mask_irq(i);
        }
    }

    logger.info("IOAPICs initialized", .{});
}

// Legacy IRQ mapping (compatible with old PIC IRQs)
pub fn configure_legacy_irqs() !void {
    const legacy_irqs = [_]struct { irq: u8, vector: u8 }{
        .{ .irq = 0, .vector = 0x20 }, // Timer (now handled by LAPIC timer)
        .{ .irq = 1, .vector = 0x21 }, // Keyboard
        .{ .irq = 3, .vector = 0x23 }, // COM2
        .{ .irq = 4, .vector = 0x24 }, // COM1
        .{ .irq = 12, .vector = 0x2C }, // PS/2 Mouse
    };

    const dest_apic_id = @as(u8, @truncate(lapic.get_id()));

    for (legacy_irqs) |mapping| {
        try configure_irq(mapping.irq, mapping.vector, dest_apic_id);
    }
}

// Get the number of registered IOAPICs
pub fn get_num_ioapics() u8 {
    return num_ioapics;
}

// Mask all interrupts on all IOAPICs
pub fn mask_all() void {
    for (ioapics[0..num_ioapics]) |*ioapic| {
        var i: u8 = 0;
        while (i < ioapic.max_entries) : (i += 1) {
            ioapic.mask_irq(i);
        }
    }
}
