const Packet = @import("packet.zig").Packet;

pub fn cmd_test(shell: anytype, _: anytype) void {
    var packet = Packet(void).init(shell.writer);
    shell.writer.print("This is a test... 0x{x:0>4}\n", .{0x42}) catch {};
    packet.type = .Success;
    packet.send();
}

pub fn ultimate_answer(shell: anytype, _: anytype) void {
    var packet = Packet(void).init(shell.writer);
    shell.writer.print("Calculating Ultimate Answer..\n", .{0x42}) catch {};
    for (0..250_000_000) |_| asm volatile ("nop");
    shell.writer.print("Calculating Trajectories\n", .{}) catch {};
    for (0..250_000_000) |_| asm volatile ("nop");
    shell.writer.print("Overlaying Grid onto Bezier Curves\n", .{}) catch {};
    for (0..250_000_000) |_| asm volatile ("nop");
    shell.writer.print("Patching Conics\n", .{}) catch {};
    for (0..250_000_000) |_| asm volatile ("nop");
    shell.writer.print("Biding Time\n", .{}) catch {};
    for (0..250_000_000) |_| asm volatile ("nop");
    shell.writer.print("Untangling Space Tape\n", .{}) catch {};
    for (0..250_000_000) |_| asm volatile ("nop");
    shell.writer.print("Recalibrating Density Scale\n", .{}) catch {};
    for (0..250_000_000) |_| asm volatile ("nop");
    shell.writer.print("The Ultimate Answer is ...\n", .{}) catch {};
    for (0..750_000_000) |_| asm volatile ("nop");
    shell.writer.print("{d}\n", .{42}) catch {};
    packet.type = .Success;
    packet.send();
}

pub fn shadok(shell: anytype, _: anytype) void {
    var packet = Packet(void).init(shell.writer);
    shell.writer.print("Ga Bu Zo Meu (ѷ)\n", .{}) catch {};
    packet.type = .Success;
    packet.send();
}

pub fn quit(_: anytype, _: anytype) void {
    @import("../../drivers/acpi/acpi.zig").power_off();
}
