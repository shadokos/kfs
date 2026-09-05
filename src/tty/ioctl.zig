// The control requests a terminal answers. POSIX exposes these as tcgetattr,
// tcsetattr and the rest, each reaching here through its own syscall. The
// numbers are ours, except the three mlibc hardcodes.

pub const Request = enum(u32) {
    /// Read the current termios.
    TCGETS = 1,
    /// Apply new termios at once.
    TCSETS = 2,
    /// Apply once the output has drained.
    TCSETSW = 3,
    /// Apply once the output has drained, discarding pending input.
    TCSETSF = 4,

    // Wired into options/posix/include/termios.h in mlibc, so not ours to pick.
    TIOCGPGRP = 0x540F,
    TIOCSPGRP = 0x5410,
    TIOCGSID = 0x5429,

    _,
};

/// When tcsetattr should take effect, POSIX 11.2.
pub const SetAction = enum(u32) {
    NOW = 0,
    /// Once the output written so far has been sent.
    DRAIN = 1,
    /// As DRAIN, and throw away the input not yet read.
    FLUSH = 2,
};
