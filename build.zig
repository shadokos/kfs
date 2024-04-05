const std = @import("std");
const Step = @import("std").build.Step;
const Builder = @import("std").build.Builder;

pub const BuildContext = struct {
    builder: *Builder,
    build_options: *Step.Options = undefined,

    // Steps
    //themes: *Step.Run = undefined,
    kernel: *Step.Compile = undefined,
    grub: *Step.Run = undefined,
    qemu: *Step.Run = undefined,
    run: *Step = undefined,

    // Installed files
    install_iso_folder: *Step.InstallDir = undefined,
    install_disk_image: *Step.InstallFile = undefined,
    install_kernel: *Step.InstallArtifact = undefined,
};

pub fn build(b: *Builder) !void {
    var context = BuildContext{ .builder = b };

    const iso_source_dir = context.builder.option(
        []const u8,
        "iso_dir",
        "Specify the iso directory source",
    ) orelse "iso";

    const name = context.builder.option(
        []const u8,
        "name",
        "Specify a name for output binary",
    ) orelse "kfs.elf";

    const posix = context.builder.option(
        bool,
        "posix",
        "Enable this flag if strict POSIX conformance is wanted",
    ) orelse false;

    @import("build/disk_image.zig").install_iso_folder(&context, iso_source_dir);
    @import("build/kernel.zig").build_executable(&context, name, posix);
    @import("build/themes.zig").install_themes(&context);
    @import("build/disk_image.zig").build_disk_image(&context);
    @import("build/qemu.zig").add_step_run(&context);
}
