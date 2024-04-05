const std = @import("std");

const BuildContext = @import("../build.zig").BuildContext;
const addDirectoryDependency = @import("Step/DirectoryDependency.zig").addDirectoryDependency;

pub fn install_themes(context: *BuildContext) void {
    const themes = context.builder.addSystemCommand(&.{
        "make",
        "-f",
        "build/Makefiles/Themes.mk",
        "install_themes",
        "--no-print-directory",
    });

    themes.setName("retrieve themes");
    context.kernel.step.dependOn(&themes.step);

    register_uninstall_themes(context);
}

pub fn register_uninstall_themes(context: *BuildContext) void {
    const uninstall_theme = context.builder.addSystemCommand(&.{ "rm", "-r", "src/tty/themes" });
    uninstall_theme.setName("uninstall themes");
    context.builder.getUninstallStep().dependOn(&uninstall_theme.step);
}
