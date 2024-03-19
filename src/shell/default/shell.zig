const utils = @import("utils.zig");
pub const Shell = @import("../Shell.zig").Shell(@import("builtins.zig"));

pub fn on_error(shell: *Shell) void {
    @import("utils.zig").ensure_newline(shell.writer);
}

pub fn pre_process(shell: *Shell) void {
    utils.print_prompt(shell);
}

pub fn pre_cmd(shell: *Shell) void {
    utils.ensure_newline(shell.writer);
}
