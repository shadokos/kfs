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

/// The termios settings changed. `old` is what they were, for a driver that
/// only wants to reprogram what actually moved.
set_termios: ?*const fn (tty: *TtyStruct, old: termios.termios) void = null,
