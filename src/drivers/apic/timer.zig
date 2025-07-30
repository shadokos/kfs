// src/drivers/apic/timer.zig
const cpu = @import("../../cpu.zig");
const pit = @import("../pit/pit.zig");
const lapic = @import("lapic.zig");
const interrupts = @import("../../interrupts.zig");
const scheduler = @import("../../task/scheduler.zig");
const logger = @import("ft").log.scoped(.apic_timer);
const tsc = @import("../../cpu/tsc.zig");

// Timer vector (using same as PIT for compatibility)
pub const TIMER_VECTOR: u8 = 0x20;

// Timer divider values
pub const TimerDivider = enum(u8) {
    Div1 = 0x0B,
    Div2 = 0x00,
    Div4 = 0x01,
    Div8 = 0x02,
    Div16 = 0x03,
    Div32 = 0x08,
    Div64 = 0x09,
    Div128 = 0x0A,
};

// Global timer state
var timer_frequency: u64 = 0;
var timer_period_ns: f64 = 0;
var timer_ticks: u64 = 0;
var timer_ticks_ptr: *volatile u64 = &timer_ticks; // Ensure visibility across cores
var timer_mode: lapic.TimerMode = .Periodic;
var timer_divider: TimerDivider = .Div1;

// Timer calibration state
const CalibrationState = struct {
    pit_ticks: u32,
    apic_ticks: u32,
    completed: bool,
};

var calibration: CalibrationState = .{
    .pit_ticks = 0,
    .apic_ticks = 0,
    .completed = false,
};

// Timer interrupt handler
pub fn timer_handler(_: interrupts.InterruptFrame) void {
    timer_ticks_ptr.* += 1;
    lapic.send_eoi();
    scheduler.schedule();
}

// Calibrate APIC timer using PIT
pub fn calibrate() !void {
    logger.debug("Calibrating APIC timer frequency", .{});

    // We'll use PIT channel 2 for calibration (doesn't interfere with system timer)
    const calibration_ms: u64 = 10;
    const pit_ticks = (pit.FREQUENCY * calibration_ms) / 1000;

    // Configure PIT channel 2 for one-shot mode
    pit.send_command(.{
        .BCD_binary_Mode = false,
        .operating_mode = .InterruptOnTerminalCount,
        .access_mode = .AccessModeBoth,
        .select_channel = .Channel_2,
    });

    // Disable speaker (bit 0) and enable gate (bit 1) for channel 2
    const port_b = cpu.inb(0x61);
    cpu.outb(0x61, (port_b & ~@as(u8, 1)) | 2);

    // Set APIC timer to maximum count with divider
    lapic.write(lapic.LAPIC_TIMER_DIVIDE, @intFromEnum(TimerDivider.Div1));
    lapic.write(lapic.LAPIC_TIMER_INITIAL_COUNT, 0xFFFFFFFF);

    // Load PIT count
    cpu.outb(pit.ch2_data, @truncate(pit_ticks));
    cpu.outb(pit.ch2_data, @truncate(pit_ticks >> 8));

    // Wait for PIT to count down
    while ((cpu.inb(0x61) & 0x20) == 0) {
        cpu.io_wait();
    }

    // Read APIC timer count
    const apic_count = lapic.read(lapic.LAPIC_TIMER_CURRENT_COUNT);
    const apic_ticks_elapsed: u64 = 0xFFFFFFFF - apic_count;

    // Calculate frequency
    timer_frequency = (apic_ticks_elapsed * 1000) / calibration_ms;
    timer_period_ns = 1_000_000_000.0 / @as(f64, @floatFromInt(timer_frequency));

    // Restore port B
    cpu.outb(0x61, port_b);

    const timer_period_ns_x1000: u64 = @intFromFloat(timer_period_ns * 1_000);
    const whole_part = timer_period_ns_x1000 / 1_000;
    const fractional_part = timer_period_ns_x1000 % 1_000;
    logger.info("APIC timer frequency: {} Hz ({}.{:0>3} ns period)", .{
        timer_frequency,
        whole_part,
        fractional_part,
    });
}

// Setup periodic timer
pub fn setup_periodic(frequency_hz: u32) !void {
    if (timer_frequency == 0) {
        return error.TimerNotCalibrated;
    }

    const initial_count = timer_frequency / frequency_hz;
    if (initial_count > 0xFFFFFFFF) {
        return error.FrequencyTooLow;
    }

    // Configure timer in periodic mode
    const lvt_timer = @as(u32, TIMER_VECTOR) | (1 << 17); // Periodic mode
    lapic.write(lapic.LAPIC_LVT_TIMER, lvt_timer);

    // Set divider
    lapic.write(lapic.LAPIC_TIMER_DIVIDE, @intFromEnum(timer_divider));

    // Set initial count (starts timer)
    lapic.write(lapic.LAPIC_TIMER_INITIAL_COUNT, @truncate(initial_count));

    timer_mode = .Periodic;
    logger.debug("Periodic timer set to {} Hz", .{frequency_hz});

    // time between 2 ticks in nanoseconds
    timer_period_ns = 1_000_000_000.0 / @as(f64, @floatFromInt(frequency_hz));
}

// Setup one-shot timer
pub fn setup_oneshot(microseconds: u32) !void {
    if (timer_frequency == 0) {
        return error.TimerNotCalibrated;
    }

    const ticks = (@as(u64, microseconds) * timer_frequency) / 1_000_000;
    if (ticks > 0xFFFFFFFF) {
        return error.DelayTooLong;
    }

    // Configure timer in one-shot mode
    const lvt_timer = TIMER_VECTOR; // One-shot mode (bit 17 = 0)
    lapic.write(lapic.LAPIC_LVT_TIMER, lvt_timer);

    // Set divider
    lapic.write(lapic.LAPIC_TIMER_DIVIDE, @intFromEnum(timer_divider));

    // Set initial count (starts timer)
    lapic.write(lapic.LAPIC_TIMER_INITIAL_COUNT, @truncate(ticks));

    timer_mode = .OneShot;
    timer_period_ns = @as(f64, @floatFromInt(microseconds)) * 1_000.0;
}

// Stop timer
pub fn stop() void {
    // Mask timer interrupt
    lapic.write(lapic.LAPIC_LVT_TIMER, 0x10000);
    lapic.write(lapic.LAPIC_TIMER_INITIAL_COUNT, 0);
}

// Get current timer count
pub fn get_current_count() u32 {
    return lapic.read(lapic.LAPIC_TIMER_CURRENT_COUNT);
}

// Sleep functions (compatible with PIT interface)
pub fn sleep_n_ticks(ticks: u64) void {
    const start = timer_ticks;
    while (timer_ticks - start < ticks) {
        cpu.halt();
    }
}

pub fn nano_sleep(ns: u64) void {
    if (timer_period_ns > 0) {
        sleep_n_ticks(@intFromFloat(@as(f64, @floatFromInt(ns)) / timer_period_ns));
    }
}

pub fn sleep(ms: u64) void {
    nano_sleep(ms * 1_000_000);
}

pub fn get_time_since_boot() u64 {
    return @intFromFloat((@as(f64, @floatFromInt(timer_ticks)) * timer_period_ns) / 1_000_000);
}

pub fn get_utime_since_boot() u64 {
    return @intFromFloat((@as(f64, @floatFromInt(timer_ticks)) * timer_period_ns) / 1_000);
}

// Initialize APIC timer
pub fn init() !void {
    logger.debug("Initializing APIC timer", .{});

    // Calibrate timer frequency
    try calibrate();

    // Setup periodic timer at 1000 Hz (same as PIT)
    try setup_periodic(100);

    // Register interrupt handler
    interrupts.set_intr_gate(TIMER_VECTOR, interrupts.Handler.create(timer_handler, false));

    logger.info("APIC timer initialized at 1000 Hz", .{});
}

// Check if TSC-deadline mode is supported
pub fn is_tsc_deadline_supported() bool {
    const result = lapic.cpuid(1, 0);
    return (result.ecx & (1 << 24)) != 0; // TSC-Deadline bit
}

// Setup TSC-deadline timer (if supported)
pub fn setup_tsc_deadline(deadline: u64) !void {
    if (!is_tsc_deadline_supported()) {
        return error.TSCDeadlineNotSupported;
    }

    // Configure timer in TSC-deadline mode
    const lvt_timer = TIMER_VECTOR | (2 << 17); // TSC-deadline mode
    lapic.write(lapic.LAPIC_LVT_TIMER, lvt_timer);

    // Write deadline to MSR
    const IA32_TSC_DEADLINE_MSR: u32 = 0x6E0;
    lapic.wrmsr(IA32_TSC_DEADLINE_MSR, deadline);

    timer_mode = .TSCDeadline;
}

// High precision delay using TSC
pub fn precise_delay_us(microseconds: u64) void {
    const start = tsc.get_time_us();
    while (tsc.get_time_us() - start < microseconds) {
        cpu.io_wait();
    }
}
