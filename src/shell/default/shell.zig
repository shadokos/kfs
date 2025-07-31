const utils = @import("../utils.zig");
pub const Shell = @import("../Shell.zig").Shell(@import("builtins.zig"));
const colors = @import("colors");
const tty = @import("../../tty/tty.zig");

pub fn on_init(shell: *Shell) void {
    var current_tty = &tty.tty_array[shell.tty_id];
    current_tty.config.c_lflag.ECHOCTL = true;

    shell.writer.print("tty {d}, Hello {s}{d}{s}\n", .{
        shell.tty_id,
        colors.green,
        42,
        colors.reset,
    }) catch {};
}

pub fn on_error(shell: *Shell) void {
    utils.ensure_newline(shell.writer);
    shell.defaultErrorHook();
}

pub fn pre_process(shell: *Shell) void {
    utils.print_prompt(shell);
}

pub fn pre_cmd(shell: *Shell) void {
    utils.ensure_newline(shell.writer);
}
