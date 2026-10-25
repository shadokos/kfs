const std = @import("std");
const Step = @import("std").Build.Step;

const BuildContext = @import("../build.zig").BuildContext;

pub fn install_themes(context: *BuildContext) *Step.Run {
    const themes = context.builder.addSystemCommand(&.{
        "make",
        "install_themes",
        "--no-print-directory",
    });
    themes.setName("retrieve themes");
    return themes;
}

pub fn uninstall_themes(context: *BuildContext) *Step {
    const uninstall_theme = context.builder.addSystemCommand(&.{
        "make",
        "theme_clean",
        "--no-print-directory",
    });
    uninstall_theme.setName("uninstall themes");
    return &uninstall_theme.step;
}
