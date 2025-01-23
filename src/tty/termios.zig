const ft = @import("ft");
const keymap = @import("keyboard/keymap.zig");

pub const NCCS = 11;

pub const tcflag_t = c_int;

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

pub const bauds = enum(tcflag_t) {
    B0 = 0,
    B50 = 50,
    B75 = 75,
    B110 = 110,
    B134 = 134.5, // ?
    B150 = 150,
    B200 = 200,
    B300 = 300,
    B600 = 600,
    B1200 = 1200,
    B1800 = 1800,
    B2400 = 2400,
    B4800 = 4800,
    B9600 = 9600,
    B19200 = 19200,
    B38400 = 38400,
};

// ignored
pub const cflags = packed struct {
    CSIZE: bool = false, // Character size:
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
