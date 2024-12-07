const std = @import("std");

const BuildContext = @import("../build.zig").BuildContext;

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
    const uninstall_theme = context.builder.addSystemCommand(&.{
        "make",
        "-f",
        "build/Makefiles/Themes.mk",
        "theme_clean",
        "--no-print-directory",
    });

    uninstall_theme.setName("uninstall themes");
    context.builder.getUninstallStep().dependOn(&uninstall_theme.step);
}
