// What a terminal needs from the hardware behind it. Every function is handed
// the TtyStruct; a driver reaches its own state through TtyStruct.driver_data.

const TtyStruct = @import("TtyStruct.zig");
const termios = @import("termios.zig");

/// Send processed output to the hardware. Returns the number of bytes taken.
write: *const fn (tty: *TtyStruct, data: []const u8) usize,

/// Push anything held back out to the hardware.
flush: ?*const fn (tty: *TtyStruct) void = null,

/// This terminal is now the one being shown, or is no longer. Only means
/// something to a driver sharing one screen between terminals.
activate: ?*const fn (tty: *TtyStruct, active: bool) void = null,

/// Take in what the hardware has to offer. Called from the input task, never
/// from the interrupt that flagged the terminal.
receive: ?*const fn (tty: *TtyStruct) void = null,

/// Wait until everything handed over has left the hardware.
///
/// A driver that has transmitted a byte by the time `write` returns has nothing
/// to wait for and leaves this null, which is what makes tcdrain a no-op on a
/// console and real on a line.
drain: ?*const fn (tty: *TtyStruct) void = null,

/// Throw away what has not been transmitted yet, for tcflush.
flush_output: ?*const fn (tty: *TtyStruct) void = null,

/// Drop the line, for HUPCL on the last close. A console has no line to drop
/// and leaves this null.
hangup: ?*const fn (tty: *TtyStruct) void = null,

/// The termios settings changed. `old` is what they were, for a driver that
/// only wants to reprogram what actually moved.
set_termios: ?*const fn (tty: *TtyStruct, old: termios.termios) void = null,
