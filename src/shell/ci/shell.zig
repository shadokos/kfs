const Serial = @import("../../drivers/serial_port/serial.zig");
const pic = @import("../../drivers/pic/pic.zig");
const ft = @import("../../ft/ft.zig");
const Packet = @import("packet.zig").Packet;
const interrupts = @import("../../interrupts.zig");

pub const Shell = @import("../Shell.zig").Shell(@import("builtins.zig"));
pub var com_port_1: Serial = Serial.init(.com_port_1);

fn pic_handler(_: *interrupts.InterruptFrame) callconv(.C) void {
    pic.ack(.COM1);
}

pub fn on_init(shell: *Shell) void {
    com_port_1.activate() catch return ft.log.err("Failed to enable COM1", .{});
    ft.log.info("COM1 enabled", .{});

    interrupts.set_trap_gate(pic.IRQ.COM1, interrupts.Handler.create(&pic_handler, false));
    pic.enable_irq(pic.IRQ.COM1);
    _ = shell.writer.write("COM1 IRQ enabled\n") catch {};
}

pub fn on_error(shell: *Shell) void {
    const err = shell.execution_context.err orelse unreachable;

    var packet = Packet(void).init(shell.writer);
    packet.err = err;
    packet.send();
}
