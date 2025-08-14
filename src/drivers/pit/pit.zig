const std = @import("std");
const tty = @import("../../tty/tty.zig");
const cpu = @import("../../cpu.zig");
const MonoState = @import("../../misc/monostate.zig").Monostate;
const pic = @import("../pic/pic.zig");
const interrupts = @import("../../interrupts.zig");
const Handler = interrupts.Handler;

const math = std.math;
const pit_logger = std.log.scoped(.driver_pit);

// The PIT driver (Intel 8254), implemented according to osdev.org
// See: https://wiki.osdev.org/Programmable_Interval_Timer

pub const FREQUENCY = 1193182; // 1193182 hz, the frequency of the crystal oscillator signal

// PIT I/O Ports
pub const ch0_data = 0x40; // Read/Write
pub const ch1_data = 0x41; // Read/Write
pub const ch2_data = 0x42; // Read/Write
pub const mode_cmd_register = 0x43; // Read

pub var interval_ns: u32 = 0;

pub const TSCInfo = struct {
    frequency_hz: u64 = 0,
    calibrated: bool = false,
    cycles_per_ns: f64 = 0.0,
    ns_per_cycle: f64 = 0.0,
};

pub fn read_tsc() u64 {
    return cpu.rdtsc();
}

const tsc = @import("../../tsc/tsc.zig");

pub fn calibrate_tsc() void {
    pit_logger.info("Calibrating TSC using PIT...", .{});

    const pit_freq = 1000; // 1kHz
    const calibration_ms = 100;
    const divisor = FREQUENCY / pit_freq;

    // Configure PIT channel 2
    write_mode_cmd(ModeCmdRegister{
        .BCD_binary_Mode = false,
        .operating_mode = OperatingMode.SquareWaveGenerator,
        .access_mode = AccessMode.AccessModeBoth,
        .select_channel = .Channel_2,
    });
    cpu.outb(ch2_data, @truncate(divisor));
    cpu.outb(ch2_data, @truncate(divisor >> 8));

    // Disable interrupts during calibration
    const flags = cpu.save_and_disable_interrupts();
    defer cpu.restore_interrupts(flags);

    // Wait for the first falling edge to synchronize
    const prev = read_status(.Channel_2).OutputPinState;
    while (read_status(.Channel_2).OutputPinState == prev) {}

    // Take initial measurements
    const start_tsc = cpu.read_tsc();
    const expected_pit_ticks = (pit_freq * calibration_ms) / 1000;

    var pit_ticks_counted: u32 = 0;
    var last_state: u1 = read_status(.Channel_2).OutputPinState;
    while (pit_ticks_counted < expected_pit_ticks) {
        const state = read_status(.Channel_2).OutputPinState;
        if (state == 1 and last_state == 0) {
            pit_ticks_counted += 1;
        }
        last_state = state;
    }

    const end_tsc = cpu.read_tsc();
    const tsc_cycles = end_tsc -% start_tsc;
    const actual_time_ns = calibration_ms * 1_000_000;

    tsc.calibrated_frequency = (tsc_cycles * 1_000_000_000) / actual_time_ns;
    tsc.tsc_per_ms = tsc.calibrated_frequency / 1_000;
    tsc.tsc_per_us = tsc.calibrated_frequency / 1_000_000;

    const ns_per_cycle_x1000 = @as(u32, @intFromFloat((@as(f64, @floatFromInt(actual_time_ns)) / @as(f64, @floatFromInt(tsc_cycles))) * 1000));
    const whole_part = ns_per_cycle_x1000 / 1000;
    const frac_part = ns_per_cycle_x1000 % 1000;

    pit_logger.info("TSC calibrated: {} Hz ({}.{:0>3} ns/cycle)", .{
        tsc.calibrated_frequency,
        whole_part,
        frac_part
    });
}


pub const OperatingMode = enum(u3) {
    InterruptOnTerminalCount,
    HardwareRetriggerableOneShot,
    RateGenerator,
    SquareWaveGenerator,
    SoftwareTriggeredStrobe,
    HardwareTriggeredStrobe,
};

pub const AccessMode = enum(u2) {
    LatchCount,
    AccessModeLoByte,
    AccessModeHiByte,
    AccessModeBoth,
};

pub const SelectChannel = enum(u2) {
    Channel_0,
    Channel_1,
    Channel_2,
};

pub const ModeCmdRegister = packed struct {
    // BCD / Binary Mode, false = 16-bit binary mode, true = four-digit BCD
    BCD_binary_Mode: bool,
    operating_mode: OperatingMode,
    access_mode: AccessMode,
    select_channel: SelectChannel,
};

pub const ReadBackStatus = packed struct {
    BCD_binary_Mode: bool,
    operating_mode: OperatingMode,
    access_mode: AccessMode,
    null_count_flags: u1,
    OutputPinState: u1,
};

pub const ReadBackCommand = packed struct {
    _: MonoState(u1, 0) = .{},
    channel_0: bool,
    channel_1: bool,
    channel_2: bool,
    latch_status: u1 = 0, // 0 = latch status, 1 = don't latch status
    latch_count: u1 = 0, // 0 = latch count, 1 = don't latch count
    cmd: MonoState(u2, 0b11) = .{},
};

pub fn write_mode_cmd(cmd: ModeCmdRegister) void {
    cpu.outb(mode_cmd_register, @bitCast(cmd));
}

fn get_channel_logger(comptime channel: SelectChannel) type {
    return switch (channel) {
        .Channel_0 => std.log.scoped(.@"pit(ch0)"),
        .Channel_1 => std.log.scoped(.@"pit(ch1)"),
        .Channel_2 => std.log.scoped(.@"pit(ch2)"),
    };
}

fn get_channel_port(channel: SelectChannel) u16 {
    return switch (channel) {
        .Channel_0 => ch0_data,
        .Channel_1 => ch1_data,
        .Channel_2 => ch2_data,
    };
}

pub fn send_read_back(cmd: ReadBackCommand) void {
    cpu.outb(mode_cmd_register, @bitCast(cmd));
}

pub fn read_status(channel: SelectChannel) ReadBackStatus {
    const channel_port = get_channel_port(channel);
    send_read_back(.{
        .channel_0 = channel == .Channel_0,
        .channel_1 = channel == .Channel_1,
        .channel_2 = channel == .Channel_2,
    });
    return @bitCast(cpu.inb(channel_port));
}

// Program PIT Channel 0 to fire a one-shot interrupt after `timeout_us` microseconds.
// Uses mode InterruptOnTerminalCount with low+high byte access.
pub fn set_timeout_us(timeout_us: u64) void {
    const channel_port = get_channel_port(.Channel_0);

    // Compute reload value (1..65536), using rounding.
    var count: u64 = (timeout_us * FREQUENCY + 500_000) / 1_000_000;
    if (count == 0) count = 1; // minimum delay
    if (count > 0x10000) count = 0x10000; // 0x10000 == 65536 when written as 0

    write_mode_cmd(ModeCmdRegister{
        .BCD_binary_Mode = false,
        .operating_mode = OperatingMode.InterruptOnTerminalCount,
        .access_mode = AccessMode.AccessModeBoth,
        .select_channel = .Channel_0,
    });
    // Writing 0 for the 16-bit reload value programs 65536.
    const reload_value: u32 = @truncate(count & 0xFFFF);
    cpu.outb(channel_port, @truncate(reload_value));
    cpu.outb(channel_port, @truncate(reload_value >> 8));
}

pub fn program_periodic(comptime channel: SelectChannel, frequency: u32) void {
    pit_logger.debug("Initializing {s} with frequency {d} hz", .{ @tagName(channel), frequency });

    const channel_port = get_channel_port(channel);
    const init_logger = get_channel_logger(channel);
    const divisor = FREQUENCY / frequency;
    const reload_value = switch (divisor) {
        0 => b: {
            init_logger.warn("Frequency too high, using maximum frequency", .{});
            break :b 1;
        },
        1...0x10000 => divisor,
        else => b: {
            init_logger.warn("Frequency too low, using minimum frequency", .{});
            break :b 0x10000;
        },
    };

    const real_frequency = (FREQUENCY + (reload_value / 2)) / reload_value;
    interval_ns = 1_000_000_000 / real_frequency;
    init_logger.debug("Using frequency {d} hz, interval {d} ns", .{ real_frequency, interval_ns });

    write_mode_cmd(ModeCmdRegister{
        .BCD_binary_Mode = false,
        .operating_mode = OperatingMode.SquareWaveGenerator,
        .access_mode = AccessMode.AccessModeBoth,
        .select_channel = channel,
    });
    cpu.outb(channel_port, @truncate(reload_value));
    cpu.outb(channel_port, @truncate(reload_value >> 8));

    const status = read_status(channel);
    init_logger.debug("Read back status: 0b{b:0>8}", .{@as(u8, @bitCast(status))});
    pit_logger.debug("{s} initialized", .{@tagName(channel)});
}
