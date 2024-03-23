const ft = @import("../../ft/ft.zig");
const Packet = @import("packet.zig").Packet;

pub fn cmd_test(shell: anytype, _: anytype) void {
    var packet = Packet(void).init(shell);
    ft.fmt.format(shell.writer, "This is a test... 0x{x:0>4}\n", .{0x42}) catch {};
    packet.type = .Success;
    packet.send();
}

pub fn quit(_: anytype, _: anytype) void {
    @import("../../drivers/acpi/acpi.zig").power_off();
}
