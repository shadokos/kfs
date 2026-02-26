const log = @import("std").log;
const tty = @import("device/tty/tty.zig");
const colors = @import("colors");
const screen_of_death = @import("screen_of_death.zig").screen_of_death;
const scheduler = @import("task/scheduler.zig");

pub fn kernel_log(
    comptime message_level: log.Level,
    comptime scope: anytype,
    comptime format: []const u8,
    args: anytype,
) void {
    const level_str = comptime message_level.asText();
    const scope_str = if (scope != .default) (@tagName(scope) ++ ": ") else "";
    const color = switch (message_level) {
        .debug => colors.cyan,
        .info => colors.green,
        .warn => colors.yellow,
        .err => colors.red,
    };
    const padding = 7 - level_str.len;

    tty.printk(
        "[" ++ color ++ level_str ++ colors.reset ++ "] " ++
            (" " ** padding) ++ scope_str ++ format ++ "\n",
        args,
    );
    tty.flush();
    if (message_level == .err and scope == .default) {
        scheduler.enter_critical();
        if (@import("build_options").ci) {
            const serial_tty = @import("drivers/tty/serial_tty.zig");
            if (serial_tty.detected_count > 0) {
                const tty_s = &@import("device/tty/tty.zig").tty_array[@import("device/tty/tty.zig").num_consoles];
                const writer = tty_s.writer().any();
                var packet = @import("shell/ci/packet.zig").Packet([]u8).init(writer);
                packet.err = error.KernelPanic;
                _ = writer.write("\n") catch {};
                packet.sendf(format, args);
            }
            @import("drivers/acpi/acpi.zig").power_off();
        } else if (@import("build_options").optimize != .Debug) {
            screen_of_death(format, args);
            while (true) @import("cpu.zig").halt();
        } else {
            const pic = @import("drivers/pic/pic.zig");
            pic.disable_all_irqs();
            pic.enable_irq(.Keyboard);

            for (0..scheduler.lock_depth) |_|
                scheduler.exit_critical();

            tty.get_tty().config.c_lflag.ECHO = false;
            tty.get_tty().config.c_lflag.ECHONL = false;

            @import("debug.zig").dump_current_stack_trace() catch {};

            while (true) {
                @import("cpu.zig").halt();
                @import("drivers/input/keyboard/keyboard.zig").kb_read();
            }
        }
    }
}
