const utils = @import("../utils.zig");
pub const Shell = @import("../Shell.zig").Shell(@import("builtins.zig"));
const colors = @import("colors");
const tty = @import("../../tty/tty.zig");

pub fn on_init(shell: *Shell) void {
    shell.writer.print("tty {d}, Hello {s}{d}{s}\n", .{
        @import("../../tty/tty.zig").current_tty,
        colors.green,
        42,
        colors.reset,
    }) catch {};
    tty.get_tty().config.c_lflag.ECHOCTL = true;
}

pub fn on_error(shell: *Shell) void {
    utils.ensure_newline(shell.writer);
    shell.defaultErrorHook();
}

pub fn pre_process(shell: *Shell) void {
    tty.flush();
    utils.print_prompt(shell);
}

pub fn pre_cmd(shell: *Shell) void {
    utils.ensure_newline(shell.writer);
}
