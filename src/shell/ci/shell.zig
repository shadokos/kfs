const std = @import("std");

pub const Shell = @import("../Shell.zig").Shell(@import("builtins.zig"));

pub fn on_init(shell: *Shell) void {
    _ = shell.writer().write("CI shell ready on ttyS0\n") catch {};
}

pub fn on_error(shell: *Shell) void {
    const Packet = @import("packet.zig").Packet;
    const err = shell.execution_context.err orelse unreachable;

    var packet = Packet(void).init(shell.writer());
    packet.err = err;
    packet.send();
}
