const utils = @import("../utils.zig");
pub const Shell = @import("../Shell.zig").Shell(@import("builtins.zig"));
const colors = @import("colors");
const tty = @import("../../tty/tty.zig");

pub fn on_init(shell: *Shell) void {
    // Dsiplay the current tty
    shell.writer.print("tty {d}, ", .{tty.current_tty}) catch {};

    // Display the motd
    shell.writer.print("Hello {s}{d}{s}\n", .{ colors.green, 42, colors.reset }) catch {};

    // get current date time from RTC
    const rtc = @import("../../drivers/rtc/rtc.zig");
    const time = rtc.get_time();
    const year: u32 = @as(u32, time.century) * 100 + time.year;

    // Display the current date time
    shell.writer.print("{d:0>4}/{d:0>2}/{d:0>2} {d:0>2}:{d:0>2}:{d:0>2} UTC ({})\n", .{
        year,
        time.month,
        time.day,
        time.hours,
        time.minutes,
        time.seconds,
        rtc.get_timestamp(),
    }) catch {};

    // Enable echoing of control characters
    tty.get_tty().config.c_lflag.ECHOCTL = true;
}

pub fn on_error(shell: *Shell) void {
    utils.ensure_newline(shell.writer);
    shell.defaultErrorHook();
}

pub fn pre_process(shell: *Shell) void {
    utils.print_prompt(shell);
}

pub fn pre_cmd(shell: *Shell) void {
    utils.ensure_newline(shell.writer);
}
