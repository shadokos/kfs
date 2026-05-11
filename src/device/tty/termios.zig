const std = @import("std");
const keymap = @import("../../drivers/input/keyboard/keymap.zig");

pub const NCCS = 11;

pub const tcflag_t = c_uint;

pub const speed_t = c_uint;

pub const cc_t = u8;

pub const cc_index = enum(usize) {
    VEOF,
    VEOL,
    VERASE,
    VINTR,
    VKILL,
    VMIN,
    VQUIT,
    VSTART,
    VSTOP,
    VSUSP,
    VTIME,
};

pub const iflags = packed struct {
    BRKINT: bool = false, // Signal interrupt on break.
    ICRNL: bool = false, // Map CR to NL on input.
    IGNBRK: bool = false, // Ignore break condition.
    IGNCR: bool = false, // Ignore CR.
    IGNPAR: bool = false, // Ignore characters with parity errors.
    INLCR: bool = false, // Map NL to CR on input.
    INPCK: bool = false, // Enable input parity check.
    ISTRIP: bool = false, // Strip character.
    IXANY: bool = false, // Enable any character to restart output.
    IXOFF: bool = false, // Enable start/stop input control.
    IXON: bool = false, // Enable start/stop output control.
    PARMRK: bool = false, // Mark parity errors.
};

pub const oflags = packed struct {
    OPOST: bool = false, // OK
    OLCUC: bool = false,
    ONLCR: bool = false, // OK
    OCRNL: bool = false, // OK
    ONOCR: bool = false, // OK
    ONLRET: bool = false, // OK
    OFILL: bool = false,
    OFDEL: bool = false,
    NL: enum(u1) {
        NL0,
        NL1,
    } = .NL0,
    CR: enum(u2) {
        CR0,
        CR1,
        CR2,
        CR3,
    } = .CR0,
    TAB: enum(u2) {
        TAB0,
        TAB1,
        TAB2,
        TAB3,
    } = .TAB0,
    BS: enum(u1) {
        BS0,
        BS1,
    } = .BS0,
    FF: enum(u1) {
        FF0,
        FF1,
    } = .FF0,
    VT: enum(u1) {
        VT0,
        VT1,
    } = .VT0,
};

pub const bauds = enum(speed_t) {
    B0 = 0,
    B50,
    B75,
    B110,
    B134, // 134.5 baud historically
    B150,
    B200,
    B300,
    B600,
    B1200,
    B1800,
    B2400,
    B4800,
    B9600,
    B19200,
    B38400,

    // Followings are not POSIX
    B57600,
    B115200,
};

/// Map a baud index to ten times the actual baud rate.
/// Uses fixed-point x10 to preserve B134's fractional part (134.5 baud = 1345).
/// For UART divisor: (base_clock * 10) / baud_to_rate_fp(b)
pub fn baud_to_rate_fp(b: bauds) u32 {
    return switch (b) {
        .B0 => 0,
        .B50 => 500,
        .B75 => 750,
        .B110 => 1100,
        .B134 => 1345, // 134.5 baud
        .B150 => 1500,
        .B200 => 2000,
        .B300 => 3000,
        .B600 => 6000,
        .B1200 => 12000,
        .B1800 => 18000,
        .B2400 => 24000,
        .B4800 => 48000,
        .B9600 => 96000,
        .B19200 => 192000,
        .B38400 => 384000,

        // Followings are not POSIX
        .B57600 => 576000,
        .B115200 => 1152000,
    };
}

/// Integer baud rate (truncated). For display purposes.
pub fn baud_to_rate(b: bauds) u32 {
    return baud_to_rate_fp(b) / 10;
}

/// Reverse lookup: find the baud index for a given integer rate.
/// Matches against the integer part (e.g. 134 matches B134).
pub fn rate_to_baud(rate: u32) ?bauds {
    inline for (std.meta.fields(bauds)) |f| {
        if (baud_to_rate(@enumFromInt(f.value)) == rate)
            return @enumFromInt(f.value);
    }
    return null;
}

pub const CharSize = enum(u2) {
    CS5 = 0, // 5 data bits
    CS6 = 1, // 6 data bits
    CS7 = 2, // 7 data bits
    CS8 = 3, // 8 data bits
};

pub const cflags = packed struct {
    CBAUD: bauds = .B38400, // Baud rate index (speed encoded in c_cflag).
    CSIZE: CharSize = .CS8, // Character size (5, 6, 7 or 8 bits).
    CSTOPB: bool = false, // Send two stop bits, else one.
    CREAD: bool = false, // Enable receiver.
    PARENB: bool = false, // Parity enable.
    PARODD: bool = false, // Odd parity, else even.
    HUPCL: bool = false, // Hang up on last close.
    CLOCAL: bool = false, // Ignore modem status lines.
};

pub const lflags = packed struct {
    ECHO: bool = false, // Enable echo.
    ECHOE: bool = false, // Echo erase character as error-correcting backspace.
    ECHOK: bool = false, // Echo KILL.
    ECHONL: bool = false, // Echo NL.
    ICANON: bool = false, // Canonical input (erase and kill processing).
    IEXTEN: bool = false, // Enable extended input character processing. todo
    ISIG: bool = false, // Enable signals.
    NOFLSH: bool = false, // Disable flush after interrupt or quit.
    TOSTOP: bool = false, // Send SIGTTOU for background output.
    ECHOCTL: bool = false, // echo ctrl chars as ^X
};

pub const termios = struct {
    c_iflag: iflags = .{ .BRKINT = true, .ICRNL = true },
    c_oflag: oflags = .{ .OPOST = true, .ONLCR = true },
    c_cflag: cflags = .{ .CREAD = true, .CLOCAL = true },
    c_lflag: lflags = .{ .ISIG = true, .ICANON = true, .ECHO = true, .IEXTEN = true, .ECHOE = true, .ECHOK = true },
    c_cc: [NCCS]cc_t = .{
        keymap.C('D'),
        keymap.C('@'),
        keymap.C('H'),
        keymap.C('C'),
        keymap.C('U'),
        0,
        keymap.C('\\'),
        keymap.C('Q'),
        keymap.C('S'),
        keymap.C('Z'),
        0,
    },
};

// POSIX speed access functions.

/// Get the output speed from c_cflag (POSIX cfgetospeed).
pub fn cfgetospeed(cfg: *const termios) bauds {
    return cfg.c_cflag.CBAUD;
}

/// Set the output speed in c_cflag (POSIX cfsetospeed).
pub fn cfsetospeed(cfg: *termios, speed: bauds) void {
    cfg.c_cflag.CBAUD = speed;
}
