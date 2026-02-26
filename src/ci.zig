const serial_tty = @import("drivers/tty/serial_tty.zig");
const tty_mod = @import("device/tty/tty.zig");

pub fn main(_: usize) u8 {
    // Use the first detected serial port (ttyS0) as the CI shell's I/O.
    if (serial_tty.detected_count == 0) {
        @import("std").log.err("CI: no serial port available", .{});
        return 1;
    }

    const tty_s = &tty_mod.tty_array[tty_mod.num_consoles];
    const ci_shell = @import("shell/ci/shell.zig");

    var shell = ci_shell.Shell.init(
        tty_s,
        .{ .colors = false },
        .{ .on_init = &ci_shell.on_init, .on_error = &ci_shell.on_error },
    );

    while (true) shell.process_line();
}
