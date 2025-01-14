const cpu = @import("../../cpu.zig");
const pic = @import("../pic/pic.zig");
const interrupts = @import("../../interrupts.zig");
const Handler = @import("../../interrupts.zig").Handler;
const logger = @import("../../ft/ft.zig").log.scoped(.driver_cmos);
const MonoState = @import("../../misc/monostate.zig").Monostate;

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
    divider_chain_reset: enum(u3) {
        DivDefault = 0b010,
        DivStop = 0b111,
    },
    update_in_progress: bool,
};

const RegisterB = packed struct {
    const InterruptType: type = packed struct {
        update_ended_interrupt: bool = false,
        alarm_interrupt: bool = false,
        periodic_interrupt: bool = false,
    };

    daylight_savings_enable: bool,
    hour_mode: HourMode,
    data_mode: DataMode,
    square_wave_enable: bool,
    interrupts: InterruptType,
    set: bool,
};

const RegisterC = packed struct {
    reserved: MonoState(u4, 0) = .{},
    update_ended_interrupt_flag: bool = false,
    alarm_interrupt_flag: bool = false,
    periodic_interrupt_flag: bool = false,
    irq_flag: bool = false,
};

const RegisterD = packed struct {
    reserved: u7,
    valid_ram: bool,
};

const RegisterF = enum(u8) {
    PowerOnReset = 0x00,
    MemorySizePass = 0x01,
    MemoryTestPass = 0x02,
    MemoryTestFail = 0x03,
    PostEndBootSystem = 0x04,
    JmpEoi = 0x05,
    ProtectedTestsPass = 0x06,
    ProtectedTestsFail = 0x07,
    MemorySizeFail = 0x08,
    Int15hBlockMove = 0x09,
    JmpNoEoi = 0x0A,
};

const rtc_address: u16 = 0x70;
const rtc_data: u16 = 0x71;
const nmi: u8 = 0x80;

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
const reg_status_f: u8 = 0xF;

const DEFAULT_CENTURY: u8 = 20;

fn read_register(reg: u8, disable_nmi: bool) u8 {
    cpu.outb(rtc_address, reg | if (disable_nmi) nmi else 0);
    return cpu.inb(rtc_data);
}

fn read_register_a(disable_nmi: bool) RegisterA {
    return @bitCast(read_register(reg_status_a, disable_nmi));
}

fn read_register_b(disable_nmi: bool) RegisterB {
    return @bitCast(read_register(reg_status_b, disable_nmi));
}

fn read_register_c(disable_nmi: bool) RegisterC {
    return @bitCast(read_register(reg_status_c, disable_nmi));
}

fn read_register_d(disable_nmi: bool) RegisterD {
    return @bitCast(read_register(reg_status_d, disable_nmi));
}

fn read_register_f(disable_nmi: bool) RegisterF {
    return @enumFromInt(read_register(reg_status_f, disable_nmi));
}

fn write_register(reg: u8, value: u8, disable_nmi: bool) void {
    cpu.outb(rtc_address, reg | if (disable_nmi) nmi else 0);
    cpu.outb(rtc_data, value);
}

fn write_register_a(value: RegisterA, disable_nmi: bool) void {
    write_register(reg_status_a, @as(u8, @bitCast(value)), disable_nmi);
}

fn write_register_b(value: RegisterB, disable_nmi: bool) void {
    write_register(reg_status_b, @as(u8, @bitCast(value)), disable_nmi);
}

fn ack_clock() void {
    _ = read_register_c(false);
}

fn bcd_to_bin(bcd: u8) u8 {
    return ((bcd >> 4) * 10) + (bcd & 0x0F);
}

fn bin_to_bcd(bin: u8) !u8 {
    if (bin > 99) return error.invalid_bcd;
    return ((bin / 10) << 4) | (bin % 10);
}

fn is_binary_coded_decimal() bool {
    return (read_register_b(false).data_mode) == .Bcd;
}

// This handler is a basic handler doing nothing bug flushing register C and logging its content
fn cmos_clock_handler(_: *interrupts.InterruptFrame) callconv(.C) void {
    logger.debug("CMOS clock interrupt: 0b{b:0>8}", .{@as(u8, @bitCast(read_register_c(false)))});
    pic.ack(.CMOSClock);
}

pub fn wait_for_rtc() void {
    while (read_register_a(false).update_in_progress) asm volatile ("nop");
}

// Read the current time from the RTC
pub fn get_time() Datetime {
    wait_for_rtc();
    return switch (is_binary_coded_decimal()) {
        false => .{
            .seconds = read_register(reg_seconds, false),
            .minutes = read_register(reg_minutes, false),
            .hours = read_register(reg_hours, false),
            .day = read_register(reg_day_of_month, false),
            .month = read_register(reg_month, false),
            .year = read_register(reg_year, false),
            .century = if (reg_century != 0) read_register(reg_century, false) else DEFAULT_CENTURY,
        },
        true => .{
            .seconds = bcd_to_bin(read_register(reg_seconds, false)),
            .minutes = bcd_to_bin(read_register(reg_minutes, false)),
            .hours = bcd_to_bin(read_register(reg_hours, false)),
            .day = bcd_to_bin(read_register(reg_day_of_month, false)),
            .month = bcd_to_bin(read_register(reg_month, false)),
            .year = bcd_to_bin(read_register(reg_year, false)),
            .century = if (reg_century != 0) bcd_to_bin(read_register(reg_century, false)) else DEFAULT_CENTURY,
        },
    };
}

pub fn set_time(time: Datetime) !void {
    // Inhibit updates ------------------ //
    var reg_b = read_register_b(false);
    reg_b.set = true;
    write_register_b(reg_b);
    // ---------------------------------- //

    // defer ensures that the A and B registers are restored to their original state even if an error occurs
    defer {
        var reg_a = read_register_a(false);
        reg_a.divider_chain_reset = .DivStop;

        reg_b.set = false;
        write_register_b(reg_b);

        reg_a.divider_chain_reset = .DivDefault;
        write_register_a(reg_a);
    }

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
            write_register(reg_seconds, try bin_to_bcd(time.seconds));
            write_register(reg_minutes, try bin_to_bcd(time.minutes));
            write_register(reg_hours, try bin_to_bcd(time.hours));
            write_register(reg_day_of_month, try bin_to_bcd(time.day));
            write_register(reg_month, try bin_to_bcd(time.month));
            write_register(reg_year, try bin_to_bcd(time.year));
            if (reg_century != 0)
                write_register(reg_century, try bin_to_bcd(time.century));
        },
    }
}

fn is_leap_year(year: u32) bool {
    return (year % 4 == 0 and (year % 100 != 0 or year % 400 == 0));
}

// EXPERIMENTAL: get timestamp from RTC in seconds since 1970/01/01 00:00:00 UTC
pub fn get_timestamp() !u32 {
    // const days_in_month = [_]u32{ 0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };

    const time = get_time();

    const years = (@as(u32, time.century) * 100 + @as(u32, time.year));
    if (years < 1970) return error.invalid_time;

    const years_since_1970 = years - 1970;
    const leap_years = (years_since_1970 + 2) / 4 - (years_since_1970 + 70) / 100 + (years_since_1970 + 370) / 400;
    const normal_years = years_since_1970 - leap_years;
    var timestamp = leap_years * 31622400 + normal_years * 31536000;

    var days: u32 = 0;
    for (0..time.month) |month| {
        days += switch (month) {
            0 => 0,
            2 => if (is_leap_year(1970 + years_since_1970)) 29 else 28,
            1, 3, 5, 7, 8, 10 => 31,
            4, 6, 9, 11 => 30,
            else => unreachable,
        };
    }
    days += @as(u32, time.day - 1);

    timestamp += days * 86400;
    timestamp += @as(u32, time.hours) * 3600;
    timestamp += @as(u32, time.minutes) * 60;
    timestamp += @as(u32, time.seconds);

    return timestamp;
}

pub fn enable_interrupts(int: RegisterB.InterruptType) void {
    // TODO:
    // remove cpu disable/enable interrupts and use lock/unlock logic instead to
    // not reenable interrupts if they were disabled before
    cpu.disable_interrupts();

    var reg_b = read_register_b(true);
    const old: u3 = @bitCast(reg_b.interrupts);
    const new: u3 = old | @as(u3, @bitCast(int));

    reg_b.interrupts = @bitCast(new);
    write_register_b(reg_b, true);

    cpu.enable_interrupts();
}

pub fn disable_interrupts(int: RegisterB.InterruptType) void {
    cpu.disable_interrupts();

    var reg_b = read_register_b(true);
    const old: u3 = @bitCast(reg_b.interrupts);
    const new: u3 = old & ~@as(u3, @bitCast(int));

    reg_b.interrupts = @bitCast(new);
    write_register_b(reg_b, true);

    cpu.enable_interrupts();
}

// Note: the new frequency can be calculated by dividing 32768 by 2^(n-1), where n is the rate
// The min rate is 3, which gives a frequency of 8192 Hz (122 µs period)
// The max rate is 15, which gives a frequency of 2 Hz (500 ms period)
pub fn set_periodic_intr_rate(rate: u4) !void {
    // rate must be above 2
    // c.f. https://wiki.osdev.org/RTC#Changing_Interrupt_Rate
    if (rate < 3 or rate > 15) return error.invalid_clock_rate;

    // TODO:
    // remove cpu disable/enable interrupts and use lock/unlock logic instead to
    // not reenable interrupts if they were disabled before
    cpu.disable_interrupts();

    var reg_a = read_register_a(true);
    reg_a.rate_selection = rate;
    write_register_a(reg_a, true);

    cpu.enable_interrupts();
}

pub fn init() void {
    logger.debug("Initializing CMOS", .{});

    logger.debug("Adding CMOS clock interrupt handler to IDT", .{});
    interrupts.set_intr_gate(.CMOSClock, Handler.create(cmos_clock_handler, false));

    // Flushing register C to prevent CMOS interrupts from being blocked
    ack_clock();

    // Display the shutdown status, because we can !
    const reg_f = read_register_f(false);
    logger.debug("Shutdown status: {s}", .{@tagName(reg_f)});

    // Retrieve the century register from the FADT
    reg_century = @import("../acpi/acpi.zig").get_acpi().fadt.century;
    logger.debug("century register: 0x{x:0>2} (retrieved from FADT)", .{reg_century});

    // Set the clock to 24-hour mode, BCD mode
    var reg_b: RegisterB = read_register_b(false);
    reg_b.hour_mode = .Hour24;
    reg_b.data_mode = .Bcd;
    reg_b.interrupts = @bitCast(@as(u3, 0));
    write_register(reg_status_b, @as(u8, @bitCast(reg_b)), false);

    pic.enable_irq(.CMOSClock);

    logger.info("CMOS initialized", .{});
}
