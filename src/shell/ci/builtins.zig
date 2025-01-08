const CmdError = @import("../Shell.zig").CmdError;
const Packet = @import("packet.zig").Packet;
const ft = @import("../../ft/ft.zig");
const utils = @import("../utils.zig");

pub fn kfuzz(shell: anytype, args: [][]u8) CmdError!void {
    if (args.len < 2) return CmdError.InvalidNumberOfArguments;

    const nb = ft.fmt.parseInt(usize, args[1], 0) catch return CmdError.InvalidParameter;
    const max_size = if (args.len == 3) ft.fmt.parseInt(
        usize,
        args[2],
        0,
    ) catch return CmdError.InvalidParameter else 10000;

    var packet = Packet(void).init(shell.writer);
    packet.type = .Success;
    packet.err = if (utils.fuzz(
        @import("../../memory.zig").smallAlloc.allocator(),
        shell.writer,
        nb,
        max_size,
        true,
    )) |_| null else |e| e;
    packet.send();
}

pub fn vfuzz(shell: anytype, args: [][]u8) CmdError!void {
    if (args.len < 2) return CmdError.InvalidNumberOfArguments;

    const nb = ft.fmt.parseInt(usize, args[1], 0) catch return CmdError.InvalidParameter;
    const max_size = if (args.len == 3) ft.fmt.parseInt(
        usize,
        args[2],
        0,
    ) catch return CmdError.InvalidParameter else 10000;

    var packet = Packet(void).init(shell.writer);
    packet.type = .Success;
    packet.err = if (utils.fuzz(
        @import("../../memory.zig").bigAlloc.allocator(),
        shell.writer,
        nb,
        max_size,
        true,
    )) |_| null else |e| e;
    packet.send();
}

pub fn quit(_: anytype, _: anytype) void {
    @import("../../drivers/acpi/acpi.zig").power_off();
}
