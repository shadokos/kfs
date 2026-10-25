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
