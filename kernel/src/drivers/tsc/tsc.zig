const std = @import("std");
const pit = @import("../pit/pit.zig");
const cpu = @import("../../cpu.zig");
const scheduler = @import("../../task/scheduler.zig");

const logger = std.log.scoped(.tsc);

pub var calibrated_frequency: u64 = 0;
pub var boot_tsc: u64 = 0;
pub var tsc_per_ms: u64 = 0;
pub var tsc_per_us: u64 = 0;
pub var tsc_per_ns: u64 = 0;
pub var tsc_overhead: u64 = 0;

pub fn init() void {
    // Calibrate the TSC frequency at boot time using the PIT.
    calibrate();
    boot_tsc = cpu.read_tsc();
}

pub fn calibrate() void {
    logger.debug("Calibrating TSC using PIT...", .{});

    const pit_freq = 1000; // 1kHz
    const calibration_ms = 100;
    const divisor = pit.FREQUENCY / pit_freq;

    // Configure PIT channel 2
    pit.write_mode_cmd(.{
        .BCD_binary_Mode = false,
        .operating_mode = .SquareWaveGenerator,
        .access_mode = .AccessModeBoth,
        .select_channel = .Channel_2,
    });
    cpu.outb(pit.ch2_data, @truncate(divisor));
    cpu.outb(pit.ch2_data, @truncate(divisor >> 8));

    // Disable interrupts during calibration
    scheduler.enter_critical();
    defer scheduler.exit_critical();

    // Wait for the first falling edge to synchronize
    const prev = pit.read_status(.Channel_2).OutputPinState;
    while (pit.read_status(.Channel_2).OutputPinState == prev) {}

    // Take initial measurements
    const start_tsc = cpu.read_tsc();
    const expected_pit_ticks = (pit_freq * calibration_ms) / 1000;

    var pit_ticks_counted: u32 = 0;
    var last_state: u1 = pit.read_status(.Channel_2).OutputPinState;
    while (pit_ticks_counted < expected_pit_ticks) {
        const state = pit.read_status(.Channel_2).OutputPinState;
        if (state == 1 and last_state == 0) {
            pit_ticks_counted += 1;
        }
        last_state = state;
    }

    const end_tsc = cpu.read_tsc();
    const tsc_cycles = end_tsc - start_tsc;
    const actual_time_ns = calibration_ms * 1_000_000;

    calibrated_frequency = (tsc_cycles * 1_000_000_000) / actual_time_ns;
    tsc_per_ms = calibrated_frequency / 1_000;
    tsc_per_us = calibrated_frequency / 1_000_000;

    const ns_per_cycle_x1000 = @as(u32, @intFromFloat(
        (@as(f64, @floatFromInt(actual_time_ns)) / @as(f64, @floatFromInt(tsc_cycles))) * 1000,
    ));
    const whole_part = ns_per_cycle_x1000 / 1000;
    const frac_part = ns_per_cycle_x1000 % 1000;

    logger.debug("TSC calibrated: {} Hz ({}.{:0>3} ns/cycle)", .{
        calibrated_frequency,
        whole_part,
        frac_part,
    });
}

pub fn tsc_overhead_measure() u64 {
    const start = cpu.read_tsc();
    const end = cpu.read_tsc();
    return end - start;
}

pub fn get_time_ns() u64 {
    const current_tsc = cpu.read_tsc();
    const tsc_delta = current_tsc - boot_tsc;
    const ns = @divTrunc(@as(u128, tsc_delta) * 1_000_000_000, calibrated_frequency);
    return @intCast(ns);
}

pub fn get_time_us() u64 {
    const current_tsc = cpu.read_tsc();
    const ms = @divTrunc(@as(u128, current_tsc - boot_tsc) * 1_000_000, calibrated_frequency);
    return @intCast(ms);
}

pub fn get_time() u64 {
    const current_tsc = cpu.read_tsc();
    const tsc_delta = current_tsc - boot_tsc;
    return tsc_delta / tsc_per_ms;
}
