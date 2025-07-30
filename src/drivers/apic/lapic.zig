// src/drivers/apic/lapic.zig
const cpu = @import("../../cpu.zig");
const paging = @import("../../memory/paging.zig");
const memory = @import("../../memory.zig");
const logger = @import("ft").log.scoped(.lapic);
const interrupts = @import("../../interrupts.zig");

// LAPIC register offsets (memory-mapped)
pub const LAPIC_ID = 0x020;
pub const LAPIC_VERSION = 0x030;
pub const LAPIC_TPR = 0x080; // Task Priority Register
pub const LAPIC_APR = 0x090; // Arbitration Priority Register
pub const LAPIC_PPR = 0x0A0; // Processor Priority Register
pub const LAPIC_EOI = 0x0B0; // End of Interrupt
pub const LAPIC_RRD = 0x0C0; // Remote Read Register
pub const LAPIC_LDR = 0x0D0; // Logical Destination Register
pub const LAPIC_DFR = 0x0E0; // Destination Format Register
pub const LAPIC_SVR = 0x0F0; // Spurious Interrupt Vector Register
pub const LAPIC_ISR = 0x100; // In-Service Register (8 registers)
pub const LAPIC_TMR = 0x180; // Trigger Mode Register (8 registers)
pub const LAPIC_IRR = 0x200; // Interrupt Request Register (8 registers)
pub const LAPIC_ESR = 0x280; // Error Status Register
pub const LAPIC_ICR_LOW = 0x300; // Interrupt Command Register (low)
pub const LAPIC_ICR_HIGH = 0x310; // Interrupt Command Register (high)

// Local Vector Table entries
pub const LAPIC_LVT_TIMER = 0x320;
pub const LAPIC_LVT_THERMAL = 0x330;
pub const LAPIC_LVT_PERF = 0x340;
pub const LAPIC_LVT_LINT0 = 0x350;
pub const LAPIC_LVT_LINT1 = 0x360;
pub const LAPIC_LVT_ERROR = 0x370;

// Timer registers
pub const LAPIC_TIMER_INITIAL_COUNT = 0x380;
pub const LAPIC_TIMER_CURRENT_COUNT = 0x390;
pub const LAPIC_TIMER_DIVIDE = 0x3E0;

// MSR registers
const IA32_APIC_BASE_MSR: u32 = 0x1B;
const IA32_APIC_BASE_BSP: u64 = 1 << 8;
const IA32_APIC_BASE_ENABLE: u64 = 1 << 11;
const IA32_APIC_BASE_X2APIC: u64 = 1 << 10;

// Default physical base address
const LAPIC_DEFAULT_BASE: u32 = 0xFEE00000;

// Timer modes
pub const TimerMode = enum(u2) {
    OneShot = 0,
    Periodic = 1,
    TSCDeadline = 2,
};

// Delivery modes for ICR
pub const DeliveryMode = enum(u3) {
    Fixed = 0,
    LowestPriority = 1,
    SMI = 2,
    Reserved = 3,
    NMI = 4,
    INIT = 5,
    StartUp = 6,
};

// Global LAPIC state
var lapic_base_virt: ?[*]volatile u32 = null;
var lapic_enabled: bool = false;
var lapic_timer_frequency: u32 = 0;
var spurious_count: u32 = 0;

// Helper functions for MSR access
inline fn rdmsr(reg: u32) u64 {
    var low: u32 = undefined;
    var high: u32 = undefined;
    asm volatile (
        \\ rdmsr
        : [low] "={eax}" (low),
          [high] "={edx}" (high),
        : [reg] "{ecx}" (reg),
    );
    return (@as(u64, high) << 32) | low;
}

inline fn wrmsr(reg: u32, value: u64) void {
    const low = @as(u32, @truncate(value));
    const high = @as(u32, @truncate(value >> 32));
    asm volatile (
        \\ wrmsr
        :
        : [reg] "{ecx}" (reg),
          [low] "{eax}" (low),
          [high] "{edx}" (high),
    );
}

// CPUID helper
fn cpuid(leaf: u32, subleaf: u32) struct { eax: u32, ebx: u32, ecx: u32, edx: u32 } {
    var eax: u32 = undefined;
    var ebx: u32 = undefined;
    var ecx: u32 = undefined;
    var edx: u32 = undefined;
    asm volatile (
        \\ cpuid
        : [eax] "={eax}" (eax),
          [ebx] "={ebx}" (ebx),
          [ecx] "={ecx}" (ecx),
          [edx] "={edx}" (edx),
        : [leaf] "{eax}" (leaf),
          [subleaf] "{ecx}" (subleaf),
    );
    return .{ .eax = eax, .ebx = ebx, .ecx = ecx, .edx = edx };
}

// Check if APIC is supported
pub fn is_supported() bool {
    const result = cpuid(1, 0);
    return (result.edx & (1 << 9)) != 0; // APIC bit
}

// Check if x2APIC is supported
pub fn is_x2apic_supported() bool {
    const result = cpuid(1, 0);
    return (result.ecx & (1 << 21)) != 0; // x2APIC bit
}

// Read LAPIC register
pub inline fn read(offset: u32) u32 {
    if (lapic_base_virt) |base| {
        return base[offset / 4];
    }
    return 0;
}

// Write LAPIC register
pub inline fn write(offset: u32, value: u32) void {
    if (lapic_base_virt) |base| {
        base[offset / 4] = value;
    }
}

// Get APIC base address from MSR
fn get_base_address() u64 {
    return rdmsr(IA32_APIC_BASE_MSR) & 0xFFFFF000;
}

// Set APIC base address
fn set_base_address(addr: u64) void {
    var value = rdmsr(IA32_APIC_BASE_MSR);
    value = (value & 0xFFF) | (addr & 0xFFFFF000);
    wrmsr(IA32_APIC_BASE_MSR, value);
}

// Enable LAPIC via MSR
fn enable_via_msr() void {
    var value = rdmsr(IA32_APIC_BASE_MSR);
    value |= IA32_APIC_BASE_ENABLE;
    wrmsr(IA32_APIC_BASE_MSR, value);
}

// Send End of Interrupt
pub fn send_eoi() void {
    write(LAPIC_EOI, 0);
}

const halt = @import("../../cpu.zig").halt;

// Initialize the Local APIC
pub fn init() void {
    logger.debug("Initializing Local APIC", .{});

    // Check if APIC is supported
    if (!is_supported()) {
        @panic("APIC not supported by CPU");
    }

    // Enable APIC in MSR
    enable_via_msr();

    // Get and map LAPIC registers
    const phys_base = get_base_address();
    logger.debug("LAPIC physical base: 0x{x}", .{@as(u64, phys_base)});

    // Map LAPIC registers to virtual memory (uncacheable)
    // const virt_base = try paging.map_mmio(@truncate(phys_base), 0x1000);
    const virt_base = memory.map_mmio(@truncate(phys_base), 0x1000) catch |err| {
        logger.err("Failed to map LAPIC registers: {s}", .{@errorName(err)});
        @panic("LAPIC initialization failed");
    };
    lapic_base_virt = @ptrCast(@alignCast(virt_base));

    logger.debug("LAPIC virtual base: 0x{x}", .{@intFromPtr(lapic_base_virt)});

    // return ;

    // Software disable first for clean state
    var svr = read(LAPIC_SVR);
    svr &= ~@as(u32, 0x100); // Clear software enable bit

    logger.debug("svr before init: 0x{x}", .{svr});

    write(LAPIC_SVR, svr);

    // Configure Destination Format Register (flat model)
    write(LAPIC_DFR, 0xFFFFFFFF);

    // Configure Logical Destination Register
    var ldr = read(LAPIC_LDR);
    ldr &= 0x00FFFFFF;
    ldr |= 0x01000000; // Logical APIC ID = 1
    write(LAPIC_LDR, ldr);

    // Set Task Priority to accept all interrupts
    write(LAPIC_TPR, 0);

    // Configure Local Vector Table entries
    // Timer (masked initially)
    write(LAPIC_LVT_TIMER, 0x10000);

    // LINT0 - ExtINT (for legacy compatibility)
    write(LAPIC_LVT_LINT0, 0x8700); // ExtINT, edge triggered, active high

    // LINT1 - NMI
    write(LAPIC_LVT_LINT1, 0x400); // NMI, edge triggered, active high

    // Error interrupt (masked)
    write(LAPIC_LVT_ERROR, 0x10000);

    // Thermal and performance monitoring (masked)
    write(LAPIC_LVT_THERMAL, 0x10000);
    write(LAPIC_LVT_PERF, 0x10000);

    // Clear Error Status Register
    write(LAPIC_ESR, 0);
    write(LAPIC_ESR, 0); // Needs two writes

    // Set Spurious Interrupt Vector and enable APIC
    // Vector 0xFF, software enable
    write(LAPIC_SVR, 0xFF | 0x100);

    // Send EOI to clear any pending interrupts
    send_eoi();

    lapic_enabled = true;
    logger.info("Local APIC initialized successfully", .{});
}

// Spurious interrupt handler
pub fn spurious_handler(_: interrupts.InterruptFrame) void {
    spurious_count += 1;
    // Do NOT send EOI for spurious interrupts
}

// Error interrupt handler
pub fn error_handler(_: interrupts.InterruptFrame) void {
    const esr = read(LAPIC_ESR);
    write(LAPIC_ESR, 0); // Clear error

    if ((esr >> 0) & 1 == 1) logger.err("LAPIC: Send checksum error", .{});
    if ((esr >> 1) & 1 == 1) logger.err("LAPIC: Receive checksum error", .{});
    if ((esr >> 2) & 1 == 1) logger.err("LAPIC: Send accept error", .{});
    if ((esr >> 3) & 1 == 1) logger.err("LAPIC: Receive accept error", .{});
    if ((esr >> 4) & 1 == 1) logger.err("LAPIC: Reserved bit error", .{});
    if ((esr >> 5) & 1 == 1) logger.err("LAPIC: Send illegal vector", .{});
    if ((esr >> 6) & 1 == 1) logger.err("LAPIC: Receive illegal vector", .{});
    if ((esr >> 7) & 1 == 1) logger.err("LAPIC: Illegal register address", .{});

    send_eoi();
}

// Get LAPIC ID
pub fn get_id() u32 {
    return read(LAPIC_ID) >> 24;
}

// Get LAPIC version
pub fn get_version() u32 {
    return read(LAPIC_VERSION) & 0xFF;
}

// Check if LAPIC is enabled
pub fn is_enabled() bool {
    return lapic_enabled;
}

// Inter-Processor Interrupt functions
pub fn send_ipi(dest: u8, vector: u8, delivery_mode: DeliveryMode) void {
    // Write destination
    write(LAPIC_ICR_HIGH, @as(u32, dest) << 24);

    // Write command with vector and delivery mode
    const icr_low = @as(u32, vector) | (@as(u32, @intFromEnum(delivery_mode)) << 8);
    write(LAPIC_ICR_LOW, icr_low);

    // Wait for delivery
    while ((read(LAPIC_ICR_LOW) & (1 << 12)) != 0) {
        cpu.io_wait();
    }
}

// Send INIT IPI to all APs
pub fn send_init_ipi_all() void {
    write(LAPIC_ICR_HIGH, 0);
    write(LAPIC_ICR_LOW, 0xC4500); // INIT, all excluding self
}

// Send startup IPI
pub fn send_startup_ipi(dest: u8, vector: u8) void {
    send_ipi(dest, vector, .StartUp);
}
