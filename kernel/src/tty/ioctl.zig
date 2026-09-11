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
    /// Throw away input, output, or both.
    TCFLSH = 5,
    /// Suspend or resume a direction of the line.
    TCXONC = 6,
    /// Wait for the output to be transmitted.
    TCDRAIN = 7,
    /// Send a break.
    TCSBRK = 8,

    // Wired into options/posix/include/termios.h in mlibc, so not ours to pick.
    /// Take this terminal as the controlling terminal of the calling session.
    TIOCSCTTY = 0x540E,
    TIOCGPGRP = 0x540F,
    TIOCSPGRP = 0x5410,
    /// Give up the controlling terminal.
    TIOCNOTTY = 0x5422,
    /// The session this terminal answers to, what tcgetsid reads.
    TIOCGSID = 0x5429,

    _,
};

/// Which queue tcflush empties, POSIX 11.2. The values are the ones mlibc's
/// shared header gives TCIFLUSH, TCOFLUSH and TCIOFLUSH.
pub const FlushQueue = enum(u32) {
    INPUT = 0,
    OUTPUT = 1,
    BOTH = 2,
    _,
};

/// What tcflow suspends or resumes, POSIX 11.2.
pub const FlowAction = enum(u32) {
    OUTPUT_OFF = 0,
    OUTPUT_ON = 1,
    /// Send a STOP character, asking the other end to stop sending.
    INPUT_OFF = 2,
    /// Send a START character.
    INPUT_ON = 3,
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
