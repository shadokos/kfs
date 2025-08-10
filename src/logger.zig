const log = @import("std").log;
const tty = @import("tty/tty.zig");
const colors = @import("colors");
const screen_of_death = @import("screen_of_death.zig").screen_of_death;

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
        @import("task/scheduler.zig").lock();
        if (@import("build_options").ci) {
            var com_port = @import("shell/ci/shell.zig").com_port_1;
            var packet = @import("shell/ci/packet.zig").Packet([]u8).init(com_port.get_writer().any());

            packet.err = error.KernelPanic;
            _ = com_port.write("\n") catch {}; // Ensure starting a new packet if we panicked in the middle of one
            packet.sendf(format, args);

            @import("drivers/acpi/acpi.zig").power_off();
        } else if (@import("build_options").optimize != .Debug) {
            screen_of_death(format, args);
            while (true) @import("cpu.zig").halt();
        } else {
            @import("drivers/pic/pic.zig").disable_all_irqs();
            @import("drivers/pic/pic.zig").enable_irq(.Keyboard);

            for (0..@import("task/scheduler.zig").lock_count) |_|
                @import("task/scheduler.zig").unlock();

            tty.get_tty().config.c_lflag.ECHO = false;
            tty.get_tty().config.c_lflag.ECHONL = false;

            @import("debug.zig").dump_current_stack_trace() catch {};

            while (true) {
                @import("cpu.zig").halt();
                @import("tty/keyboard.zig").kb_read();
            }
        }
    }
}
