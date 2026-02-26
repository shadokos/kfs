// Hardware backend vtable for TTY devices.
//
// Each backend (VGA console, serial port, ...) implements this interface.
// The TTY core calls these functions after line discipline processing.
const TtyStruct = @import("tty_struct.zig");
const termios = @import("termios.zig");

const CharError = @import("../char/char.zig").CharError;

const Self = @This();

/// Write processed output to hardware. Returns bytes written.
write: *const fn (tty: *TtyStruct, data: []const u8) usize,

/// Put a single character to hardware (used for echo).
/// If null, the core uses write() with a 1-byte slice instead.
put_char: ?*const fn (tty: *TtyStruct, c: u8) void = null,

/// Flush pending output to hardware.
flush: ?*const fn (tty: *TtyStruct) void = null,

/// Called when termios settings change (baud rate, line params, ...).
set_termios: ?*const fn (tty: *TtyStruct, old: termios.termios) void = null,

/// Driver-specific ioctl.
ioctl: ?*const fn (tty: *TtyStruct, cmd: u32, arg: usize) CharError!usize = null,

/// Poll hardware for incoming data and feed it into the input buffer.
/// Called by TtyStruct.read() when blocking for input.
receive: ?*const fn (tty: *TtyStruct) void = null,
