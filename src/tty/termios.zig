const ft = @import("../ft/ft.zig");

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


// todo
pub const BRKINT : tcflag_t = 1;	// Signal interrupt on break.
pub const ICRNL : tcflag_t = 2;		// Map CR to NL on input.
pub const IGNBRK : tcflag_t = 4;	// Ignore break condition.
pub const IGNCR : tcflag_t = 8;		// Ignore CR.
pub const IGNPAR : tcflag_t = 16;	// Ignore characters with parity errors.
pub const INLCR : tcflag_t = 32;	// Map NL to CR on input.
pub const INPCK : tcflag_t = 64;	// Enable input parity check.
pub const ISTRIP : tcflag_t = 128;	// Strip character.
pub const IXANY : tcflag_t = 256;	// Enable any character to restart output.
pub const IXOFF : tcflag_t = 512;	// Enable start/stop input control.
pub const IXON : tcflag_t = 1024;	// Enable start/stop output control.
pub const PARMRK : tcflag_t = 2048;	// Mark parity errors.

pub const OPOST : tcflag_t = 0o000001; // OK
pub const OLCUC : tcflag_t = 0o000002;
pub const ONLCR : tcflag_t = 0o000004; // OK
pub const OCRNL : tcflag_t = 0o000010; // OK
pub const ONOCR : tcflag_t = 0o000020; // OK
pub const ONLRET : tcflag_t = 0o000040; // OK
pub const OFILL : tcflag_t = 0o000100;
pub const OFDEL : tcflag_t = 0o000200;
pub const NLDLY : tcflag_t = 0o000400;
pub const NL0 : tcflag_t = 0o000000;
pub const NL1 : tcflag_t = 0o000400;
pub const CRDLY : tcflag_t = 0o003000;
pub const CR0 : tcflag_t = 0o000000;
pub const CR1 : tcflag_t = 0o001000;
pub const CR2 : tcflag_t = 0o002000;
pub const CR3 : tcflag_t = 0o003000;
pub const TABDLY : tcflag_t = 0o014000;
pub const TAB0 : tcflag_t = 0o000000;
pub const TAB1 : tcflag_t = 0o004000;
pub const TAB2 : tcflag_t = 0o010000;
pub const TAB3 : tcflag_t = 0o014000;
pub const BSDLY : tcflag_t = 0o020000;
pub const BS0 : tcflag_t = 0o000000;
pub const BS1 : tcflag_t = 0o020000;
pub const FFDLY : tcflag_t = 0o100000;
pub const FF0 : tcflag_t = 0o000000;
pub const FF1 : tcflag_t = 0o100000;
pub const VTDLY : tcflag_t = 0o040000;
pub const VT0 : tcflag_t = 0o000000;
pub const VT1 : tcflag_t = 0o040000;

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
pub const CSIZE: tcflag_t = 1;   // Character size:
pub const CSTOPB: tcflag_t = 2;   // Send two stop bits, else one.
pub const CREAD: tcflag_t = 4;   // Enable receiver.
pub const PARENB: tcflag_t = 8;   // Parity enable.
pub const PARODD: tcflag_t= 16;   // Odd parity, else even.
pub const HUPCL: tcflag_t= 32;   // Hang up on last close.
pub const CLOCAL: tcflag_t= 64;   // Ignore modem status lines.

pub const ECHO : tcflag_t = 1; // Enable echo.
pub const ECHOE : tcflag_t = 2; // Echo erase character as error-correcting backspace.
pub const ECHOK : tcflag_t = 4; // Echo KILL.
pub const ECHONL : tcflag_t = 8; // Echo NL.
pub const ICANON : tcflag_t = 16; // Canonical input (erase and kill processing).
pub const IEXTEN : tcflag_t = 32; // Enable extended input character processing. todo
pub const ISIG : tcflag_t = 64; // Enable signals.
pub const NOFLSH : tcflag_t = 128; // Disable flush after interrupt or quit.
pub const TOSTOP : tcflag_t = 256; // Send SIGTTOU for background output.
pub const ECHOCTL : tcflag_t = 512; // echo ctrl chars as ^X

fn ctrl(c: u8) u8 {return (c & 0b00011111);}

pub const termios = extern struct {
	c_iflag : tcflag_t = (BRKINT | ICRNL),
	c_oflag : tcflag_t = (OPOST | ONLCR),
	c_cflag : tcflag_t = (CREAD | CLOCAL),
	c_lflag : tcflag_t = (ISIG | ICANON | ECHO | IEXTEN | ECHOE | ECHOK),
	c_cc : [NCCS]cc_t = .{
		ctrl('D'),
		ctrl('@'),
		ctrl('H'),
		ctrl('C'),
		ctrl('U'),
		0,
		ctrl('\\'),
		ctrl('Q'),
		ctrl('S'),
		ctrl('Z'),
		0
	}
};