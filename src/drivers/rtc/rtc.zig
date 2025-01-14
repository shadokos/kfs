const cpu = @import("../../cpu.zig");

const logger = @import("../../ft/ft.zig").log.scoped(.driver_rtc);

pub const Datetime = packed struct {
    seconds: u8 = 0,
    minutes: u8 = 0,
    hours: u8 = 0,
    day: u8 = 0,
    month: u8 = 0,
    year: u8 = 0,
    century: u8 = 0,
};

const DataMode = enum(u1) {
    Bcd = 0,
    Bin = 1,
};

const HourMode = enum(u1) {
    Hour12 = 0,
    Hour24 = 1,
};

const RegisterA = packed struct {
    rate_selection: u4,
    divider_chain_reset: u3,
    update_in_progress: bool,
};

const RegisterB = packed struct {
    daylight_savings_enable: bool,
    hour_mode: HourMode,
    data_mode: DataMode,
    square_wave_enable: bool,
    update_ended_interrupt_enable: bool,
    alarm_interrupt_enable: bool,
    periodic_interrupt_enable: bool,
    set: bool,
};

const RegisterC = packed struct {
    reserved: u4,
    update_ended_interrupt_flag: bool,
    alarm_interrupt_flag: bool,
    periodic_interrupt_flag: bool,
    irq_flag: bool,
};

const RegisterD = packed struct {
    reserved: u7,
    valid_ram: bool,
};

const rtc_address: u16 = 0x70;
const rtc_data: u16 = 0x71;

const reg_seconds: u8 = 0x0;
const reg_minutes: u8 = 0x2;
const reg_hours: u8 = 0x4;
const reg_day_of_week: u8 = 0x6;
const reg_day_of_month: u8 = 0x7;
const reg_month: u8 = 0x8;
const reg_year: u8 = 0x9;
var reg_century: u8 = 0x0;
const reg_status_a: u8 = 0xA;
const reg_status_b: u8 = 0xB;
const reg_status_c: u8 = 0xC;
const reg_status_d: u8 = 0xD;

const DEFAULT_CENTURY: u8 = 20;

fn read_register(reg: u8) u8 {
    cpu.outb(rtc_address, reg);
    return cpu.inb(rtc_data);
}

fn read_register_a() RegisterA {
    return @bitCast(read_register(reg_status_a));
}

fn read_register_b() RegisterB {
    return @bitCast(read_register(reg_status_b));
}

fn read_register_c() RegisterC {
    return @bitCast(read_register(reg_status_c));
}

fn read_register_d() RegisterD {
    return @bitCast(read_register(reg_status_d));
}

fn write_register(reg: u8, value: u8) void {
    cpu.outb(rtc_address, reg);
    cpu.outb(rtc_data, value);
}

fn write_register_a(value: RegisterA) void {
    write_register(reg_status_a, @bitCast(value));
}

fn write_register_b(value: RegisterB) void {
    write_register(reg_status_b, @bitCast(value));
}

fn write_register_c(value: RegisterC) void {
    write_register(reg_status_c, @bitCast(value));
}

fn write_register_d(value: RegisterD) void {
    write_register(reg_status_d, @bitCast(value));
}

fn bcd_to_bin(bcd: u8) u8 {
    return ((bcd >> 4) * 10) + (bcd & 0x0F);
}

fn bin_to_bcd(bin: u8) u8 {
    return ((bin / 10) << 4) | (bin % 10);
}

fn is_binary_coded_decimal() bool {
    return (read_register_b().data_mode) == .Bcd;
}

pub fn wait_for_rtc() void {
    @setRuntimeSafety(true);
    while (read_register_a().update_in_progress) {}
}

// Read the current time from the RTC
pub fn get_time() Datetime {
    wait_for_rtc();
    return switch (is_binary_coded_decimal()) {
        false => .{
            .seconds = read_register(reg_seconds),
            .minutes = read_register(reg_minutes),
            .hours = read_register(reg_hours),
            .day = read_register(reg_day_of_month),
            .month = read_register(reg_month),
            .year = read_register(reg_year),
            .century = if (reg_century != 0) read_register(reg_century) else DEFAULT_CENTURY,
        },
        true => .{
            .seconds = bcd_to_bin(read_register(reg_seconds)),
            .minutes = bcd_to_bin(read_register(reg_minutes)),
            .hours = bcd_to_bin(read_register(reg_hours)),
            .day = bcd_to_bin(read_register(reg_day_of_month)),
            .month = bcd_to_bin(read_register(reg_month)),
            .year = bcd_to_bin(read_register(reg_year)),
            .century = if (reg_century != 0) bcd_to_bin(read_register(reg_century)) else DEFAULT_CENTURY,
        },
    };
}

pub fn set_time(time: Datetime) void {
    switch (is_binary_coded_decimal()) {
        false => {
            write_register(reg_seconds, time.seconds);
            write_register(reg_minutes, time.minutes);
            write_register(reg_hours, time.hours);
            write_register(reg_day_of_month, time.day);
            write_register(reg_month, time.month);
            write_register(reg_year, time.year);
            if (reg_century != 0)
                write_register(reg_century, time.century);
        },
        true => {
            write_register(reg_seconds, bin_to_bcd(time.seconds));
            write_register(reg_minutes, bin_to_bcd(time.minutes));
            write_register(reg_hours, bin_to_bcd(time.hours));
            write_register(reg_day_of_month, bin_to_bcd(time.day));
            write_register(reg_month, bin_to_bcd(time.month));
            write_register(reg_year, bin_to_bcd(time.year));
            if (reg_century != 0)
                write_register(reg_century, bin_to_bcd(time.century));
        },
    }
}

// TODO: Add support for setting interrupts (alarm, periodic, update ended)

fn is_leap_year(year: u32) bool {
    return (year % 4 == 0 and (year % 100 != 0 or year % 400 == 0));
}

// EXPERIMENTAL: get timestamp from RTC in seconds since 1970/01/01 00:00:00 UTC
pub fn get_timestamp() u32 {
    const days_in_month = [_]u32{ 0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };

    const time = get_time();

    const years_since_1970 = (@as(u32, time.century) * 100 + @as(u32, time.year)) - 1970;
    const leap_years = (years_since_1970 + 2) / 4 - (years_since_1970 + 70) / 100 + (years_since_1970 + 370) / 400;
    const normal_years = years_since_1970 - leap_years;
    var timestamp = leap_years * 31622400 + normal_years * 31536000;

    var days: u32 = 0;
    for (0..time.month) |month| {
        days += if (month == 2 and is_leap_year(1970 + years_since_1970)) 29 else days_in_month[month];
    }
    days += @as(u32, time.day - 1);

    timestamp += days * 86400;
    timestamp += @as(u32, time.hours) * 3600;
    timestamp += @as(u32, time.minutes) * 60;
    timestamp += @as(u32, time.seconds);

    return timestamp;
}

pub fn init() void {
    logger.debug("Initializing RTC", .{});

    // Retrieve the century register from the FADT
    reg_century = @import("../acpi/acpi.zig").get_acpi().fadt.century;
    logger.debug("century register: 0x{x:0>2} (retrieved from FADT)", .{reg_century});

    // Setting up the hour mode to 24 hours and data mode to BCD
    var reg_b = read_register_b();
    reg_b.hour_mode = .Hour24;
    reg_b.data_mode = .Bcd;
    write_register_b(reg_b);

    logger.info("RTC initialized", .{});
}
