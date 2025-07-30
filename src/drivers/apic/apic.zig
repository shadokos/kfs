// src/drivers/apic/apic.zig
const cpu = @import("../../cpu.zig");
const acpi = @import("../acpi/acpi.zig");
const interrupts = @import("../../interrupts.zig");
const logger = @import("ft").log.scoped(.apic);

pub const lapic = @import("lapic.zig");
pub const ioapic = @import("ioapic.zig");
pub const timer = @import("timer.zig");

// APIC interrupt vectors
pub const SPURIOUS_VECTOR: u8 = 0xFF;
pub const ERROR_VECTOR: u8 = 0xFE;

// IRQ enumeration (compatible with PIC IRQ enum)
pub const IRQ = enum(u8) {
    Timer = 0,
    Keyboard = 1,
    Cascade = 2, // Not used with APIC but kept for compatibility
    COM2 = 3,
    COM1 = 4,
    LPT2 = 5,
    FloppyDisk = 6,
    LPT1 = 7,
    CMOSClock = 8,
    Free1 = 9,
    Free2 = 10,
    Free3 = 11,
    PS2Mouse = 12,
    Coprocessor = 13,
    PrimaryATAHardDisk = 14,
    SecondaryATAHardDisk = 15,

    // Extended IRQs available with IOAPIC
    PCI0 = 16,
    PCI1 = 17,
    PCI2 = 18,
    PCI3 = 19,
    // ... up to 23 typically
};

// Global APIC state
var apic_initialized: bool = false;

// IRQ to vector mapping (base vector 0x20 to avoid CPU exceptions)
const IRQ_BASE_VECTOR: u8 = 0x20;

// Get interrupt vector for an IRQ
pub fn get_vector_for_irq(irq: IRQ) u8 {
    return IRQ_BASE_VECTOR + @intFromEnum(irq);
}

// Get IRQ from interrupt vector
pub fn get_irq_from_vector(vector: u8) ?IRQ {
    if (vector >= IRQ_BASE_VECTOR and vector < IRQ_BASE_VECTOR + 24) {
        return @enumFromInt(vector - IRQ_BASE_VECTOR);
    }
    return null;
}

// Disable legacy 8259 PIC
fn disable_legacy_pic() void {
    logger.debug("Disabling legacy 8259 PIC", .{});

    // Remap PIC to avoid conflicts (vectors 0xF0-0xFF)
    cpu.outb(0x20, 0x11); // Start init sequence
    cpu.io_wait();
    cpu.outb(0xA0, 0x11);
    cpu.io_wait();

    cpu.outb(0x21, 0xF0); // Master PIC vector offset
    cpu.io_wait();
    cpu.outb(0xA1, 0xF8); // Slave PIC vector offset
    cpu.io_wait();

    cpu.outb(0x21, 0x04); // Tell Master PIC about slave
    cpu.io_wait();
    cpu.outb(0xA1, 0x02); // Tell Slave PIC its cascade identity
    cpu.io_wait();

    cpu.outb(0x21, 0x01); // 8086 mode
    cpu.io_wait();
    cpu.outb(0xA1, 0x01);
    cpu.io_wait();

    // Mask all interrupts
    cpu.outb(0x21, 0xFF);
    cpu.outb(0xA1, 0xFF);

    logger.info("Legacy PIC disabled and masked", .{});
}

// Parse ACPI MADT table
fn parse_madt() !void {
    logger.debug("Parsing ACPI MADT for APIC configuration", .{});

    // This would normally interface with your ACPI driver
    // For now, we'll register the default IOAPIC
    try ioapic.register_ioapic(0, 0xFEC00000, 0);

    // Register common IRQ overrides if any
    // Example: ACPI often specifies IRQ0 (timer) override
    // ioapic.register_irq_override(0, 2, false, false);
}

// Enable an IRQ
pub fn enable_irq(irq: IRQ) void {
    const vector = get_vector_for_irq(irq);
    const cpu_id = @as(u8, @truncate(lapic.get_id()));

    ioapic.configure_irq(@intFromEnum(irq), vector, cpu_id) catch |err| {
        logger.err("Failed to enable IRQ {}: {s}", .{ @intFromEnum(irq), @errorName(err) });
    };
}

// Disable an IRQ
pub fn disable_irq(irq: IRQ) void {
    // Find the IOAPIC handling this IRQ
    if (ioapic.find_ioapic_for_gsi(@intFromEnum(irq))) |io| {
        io.mask_irq(@intFromEnum(irq));
    }
}

// Send End of Interrupt
pub inline fn ack(irq: IRQ) void {
    _ = irq; // IRQ parameter kept for compatibility
    lapic.send_eoi();
}

// Check for spurious interrupt (always handled by LAPIC)
pub fn ack_spurious_interrupt(id: u8) bool {
    _ = id;
    // Spurious interrupts are handled differently in APIC
    // They have their own vector and don't need special checking
    return false;
}

// Initialize APIC system
pub fn init() void {
    logger.debug("Initializing APIC system", .{});

    // Check CPU support
    if (!lapic.is_supported()) {
        @panic("CPU does not support APIC");
    }

    // Disable legacy PIC first
    disable_legacy_pic();

    // Initialize Local APIC
    lapic.init();

    // Parse ACPI MADT for IOAPIC configuration
    parse_madt() catch |err| {
        logger.err("Failed to parse MADT: {s}", .{@errorName(err)});
        // Continue with default configuration
    };

    // Initialize IOAPICs
    ioapic.init() catch |err| {
        logger.err("Failed to initialize IOAPICs: {s}", .{@errorName(err)});
        @panic("IOAPIC initialization failed");
    };

    // // Configure legacy IRQ mappings
    ioapic.configure_legacy_irqs() catch |err| {
        logger.err("Failed to configure legacy IRQs: {s}", .{@errorName(err)});
    };

    // Setup interrupt handlers
    interrupts.set_intr_gate(SPURIOUS_VECTOR, interrupts.Handler.create(lapic.spurious_handler, false));
    interrupts.set_intr_gate(ERROR_VECTOR, interrupts.Handler.create(lapic.error_handler, false));

    @import("../pit/pit.zig").init();

    // Initialize APIC timer (replaces PIT for scheduling)
    timer.init() catch |err| {
        logger.err("Failed to initialize APIC timer: {s}", .{@errorName(err)});
        @panic("APIC timer initialization failed");
    };

    apic_initialized = true;
    logger.info("APIC system initialized successfully", .{});
}

// Get number of spurious interrupts (for statistics)
pub fn get_spurious_count() u32 {
    return lapic.spurious_count;
}

// Check if APIC is initialized
pub fn is_initialized() bool {
    return apic_initialized;
}

// SMP support functions (for future use)
pub const SMP = struct {
    // Send INIT IPI to all APs
    pub fn wake_all_aps() void {
        lapic.send_init_ipi_all();
    }

    // Send startup IPI to specific CPU
    pub fn send_startup_ipi(cpu_id: u8, start_vector: u8) void {
        lapic.send_startup_ipi(cpu_id, start_vector);
    }

    // Send IPI to specific CPU
    pub fn send_ipi(cpu_id: u8, vector: u8) void {
        lapic.send_ipi(cpu_id, vector, .Fixed);
    }

    // Send IPI to all CPUs except self
    pub fn send_ipi_all_except_self(vector: u8) void {
        lapic.write(lapic.LAPIC_ICR_HIGH, 0);
        lapic.write(lapic.LAPIC_ICR_LOW, vector | (1 << 18) | (1 << 19)); // All except self
    }
};

// Compatibility layer for existing PIC code
pub const compat = struct {
    // These functions provide a compatibility layer for code expecting PIC interface

    pub fn enable_all_irqs() void {
        // With APIC, we selectively enable IRQs as needed
        logger.warn("enable_all_irqs called - APIC uses selective enabling", .{});
    }

    pub fn disable_all_irqs() void {
        ioapic.mask_all();
    }

    pub fn get_interrupt_id_from_irq(irq: IRQ) !u8 {
        return get_vector_for_irq(irq);
    }

    pub fn get_irq_from_interrupt_id(id: u8) IRQ {
        return get_irq_from_vector(id) orelse error.InvalidVector;
    }
};
