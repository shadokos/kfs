const ci_shell = @import("shell/ci/shell.zig");

pub fn main() void {
    var shell = ci_shell.Shell.init(
        ci_shell.com_port_1.get_reader().any(),
        ci_shell.com_port_1.get_writer().any(),
        .{ .colors = false },
        .{ .on_init = &ci_shell.on_init, .on_error = &ci_shell.on_error },
    );

    while (true) shell.process_line();
}
