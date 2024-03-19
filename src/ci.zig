const Shell = @import("shell/Shell.zig").Shell(@import("shell/ci/builtins.zig"));
const Serial = @import("drivers/serial_port/serial.zig");
const pic = @import("drivers/pic/pic.zig");
const ft = @import("ft/ft.zig");
const cpu = @import("cpu.zig");
const tty = @import("tty/tty.zig");

var com_port_1: Serial = Serial.init(.com_port_1);
var shell = Shell.init(com_port_1.get_reader().any(), com_port_1.get_writer().any(), .{
    .colors = false,
}, .{});

fn handler() callconv(.Interrupt) void {
    pic.ack();
}

pub var packet = {};

pub fn main() void {
    const interrupts = @import("interrupts.zig");

    com_port_1.activate() catch return ft.log.err("Failed to enable COM1", .{});

    interrupts.set_trap_gate(pic.IRQS.COM1, interrupts.Handler{ .noerr = &handler });
    pic.enable_irq(pic.IRQS.COM1);

    while (true) shell.process_line();
}
