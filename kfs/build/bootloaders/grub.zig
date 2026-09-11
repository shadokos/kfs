const std = @import("std");
const Step = @import("std").Build.Step;

const BuildContext = @import("../../build.zig").BuildContext;
const addDirectoryDependency = @import("../Step/DirectoryDependency.zig").addDirectoryDependency;

pub fn install_iso_folder(context: *BuildContext) *Step.InstallDir {
    return context.builder.addInstallDirectory(.{
        .source_dir = .{ .cwd_relative = context.iso_source_dir },
        .install_dir = .prefix,
        .install_subdir = "iso",
    });
}

pub fn build_disk_image(context: *BuildContext, kernel: *Step.InstallArtifact) *Step.InstallFile {
    const install_iso_path = context.builder.pathResolve(&.{ context.builder.install_prefix, "iso" });

    const grub = context.builder.addSystemCommand(&.{
        "grub-mkrescue",
        "--compress=xz",
        "-o",
    });
    const iso_file = grub.addOutputFileArg("kfs.iso");
    grub.addDirectoryArg(.{ .cwd_relative = install_iso_path });

    const directory_step = addDirectoryDependency(
        grub,
        .{ .cwd_relative = context.iso_source_dir },
    );

    directory_step.step.dependOn(&install_iso_folder(context).step);
    directory_step.step.dependOn(&kernel.step);

    return context.builder.addInstallFile(iso_file, "../kfs.iso");
}
