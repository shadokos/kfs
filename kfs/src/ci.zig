const ci_shell = @import("shell/ci/shell.zig");

pub fn main(_: usize) u8 {
    var shell = ci_shell.Shell.init(
        ci_shell.line.get_reader().any(),
        ci_shell.line.get_writer().any(),
        .{ .colors = false },
        .{ .on_init = &ci_shell.on_init, .on_error = &ci_shell.on_error },
    );

    while (true) shell.process_line();
}
