const ft = @import("../../ft/ft.zig");

pub fn cmd_test(shell: anytype, _: anytype) void {
    ft.fmt.format(shell.writer, "This is a test... 0x{x:0>4}\n", .{0x42}) catch {};
}

pub fn quit(_: anytype, _: anytype) void {
    @import("../../drivers/acpi/acpi.zig").power_off();
}
