const keymap = @import("../drivers/input/keyboard/keymap.zig");

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
    // IXON on by default: Ctrl-S and Ctrl-Q are what every terminal does.
    c_iflag: iflags = .{ .BRKINT = true, .ICRNL = true, .IXON = true },
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

/// The shape a terminal takes when it crosses into userspace.
///
/// The kernel keeps its own `termios` above and converts at the syscall
/// boundary, so the two can change independently. Flags are numbered by what is
/// honoured, and the speed is bits per second in its own field rather than an
/// index in c_cflag. B134 loses its half.
pub const abi = struct {
    /// Spelled out rather than aliased: abi-bits/termios.h declares these.
    pub const flag_word = u32;
    pub const speed = u32;
    pub const control_char = u8;

    pub const iflag = packed struct(flag_word) {
        // Honoured.
        ISTRIP: bool = false,
        ICRNL: bool = false,
        INLCR: bool = false,
        IGNCR: bool = false,
        // Declared only.
        BRKINT: bool = false,
        IGNBRK: bool = false,
        IGNPAR: bool = false,
        INPCK: bool = false,
        PARMRK: bool = false,
        IXON: bool = false,
        IXOFF: bool = false,
        IXANY: bool = false,
        _: u20 = 0,
    };

    pub const oflag = packed struct(flag_word) {
        // Honoured.
        OPOST: bool = false,
        ONLCR: bool = false,
        OCRNL: bool = false,
        ONLRET: bool = false,
        // Declared only.
        OLCUC: bool = false,
        ONOCR: bool = false,
        OFILL: bool = false,
        OFDEL: bool = false,
        _: u24 = 0,
    };

    /// Nothing here is honoured yet: these describe a line, not a screen.
    pub const cflag = packed struct(flag_word) {
        CSIZE: bool = false,
        CSTOPB: bool = false,
        CREAD: bool = false,
        PARENB: bool = false,
        PARODD: bool = false,
        HUPCL: bool = false,
        CLOCAL: bool = false,
        _: u25 = 0,
    };

    pub const lflag = packed struct(flag_word) {
        // Honoured.
        ICANON: bool = false,
        ECHO: bool = false,
        ECHOE: bool = false,
        ECHOK: bool = false,
        ECHONL: bool = false,
        ECHOCTL: bool = false,
        ISIG: bool = false,
        NOFLSH: bool = false,
        // Declared only.
        IEXTEN: bool = false,
        TOSTOP: bool = false,
        _: u22 = 0,
    };

    /// Named rather than left to the compiler, the same layout being written
    /// by hand in abi-bits/termios.h.
    pub const Termios = extern struct {
        c_iflag: iflag,
        c_oflag: oflag,
        c_cflag: cflag,
        c_lflag: lflag,
        c_cc: [NCCS]control_char,
        c_ibaud: speed,
        c_obaud: speed,
    };
};

/// Build an ABI flag word from the kernel's own. Mapped by name and not by
/// bit: renaming a flag stops the build instead of quietly dropping it.
fn to_abi_flags(comptime Abi: type, kernel: anytype) Abi {
    var out: Abi = .{};
    inline for (@typeInfo(Abi).@"struct".fields) |field| {
        if (comptime field.name[0] == '_') continue;
        @field(out, field.name) = @field(kernel, field.name);
    }
    return out;
}

/// The reverse. Flags the kernel has and the ABI does not keep their default.
fn from_abi_flags(comptime Kernel: type, word: anytype) Kernel {
    var out: Kernel = .{};
    inline for (@typeInfo(@TypeOf(word)).@"struct".fields) |field| {
        if (comptime field.name[0] == '_') continue;
        @field(out, field.name) = @field(word, field.name);
    }
    return out;
}

/// What userspace is handed for this terminal.
pub fn to_abi(self: termios) abi.Termios {
    return .{
        .c_iflag = to_abi_flags(abi.iflag, self.c_iflag),
        .c_oflag = to_abi_flags(abi.oflag, self.c_oflag),
        .c_cflag = to_abi_flags(abi.cflag, self.c_cflag),
        .c_lflag = to_abi_flags(abi.lflag, self.c_lflag),
        .c_cc = self.c_cc,
        .c_ibaud = 0,
        .c_obaud = 0,
    };
}

/// What userspace asked for, in the terms the line discipline works in.
pub fn from_abi(new: abi.Termios) termios {
    return .{
        .c_iflag = from_abi_flags(iflags, new.c_iflag),
        .c_oflag = from_abi_flags(oflags, new.c_oflag),
        .c_cflag = from_abi_flags(cflags, new.c_cflag),
        .c_lflag = from_abi_flags(lflags, new.c_lflag),
        .c_cc = new.c_cc,
    };
}
