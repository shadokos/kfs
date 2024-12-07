const std = @import("std");

const BuildContext = @import("../build.zig").BuildContext;
const addDirectoryDependency = @import("Step/DirectoryDependency.zig").addDirectoryDependency;

pub fn install_iso_folder(context: *BuildContext) void {
    context.install_iso_folder = context.builder.addInstallDirectory(.{
        .source_dir = .{ .cwd_relative = context.iso_source_dir },
        .install_dir = .prefix,
        .install_subdir = "iso",
    });
}

pub fn build_disk_image(context: *BuildContext) void {
    context.grub = context.builder.addSystemCommand(&.{
        "grub-mkrescue",
        "--compress=xz",
        "-o",
    });
    const iso_file = context.grub.addOutputFileArg("kfs.iso");
    context.grub.addDirectoryArg(.{ .cwd_relative = context.install_path_iso });

    const directory_step = addDirectoryDependency(
        context.grub,
        .{ .cwd_relative = context.install_path_iso },
    );

    directory_step.step.dependOn(&context.install_iso_folder.step);
    directory_step.step.dependOn(&context.install_kernel.step);

    context.install_disk_image = context.builder.addInstallFile(iso_file, "../kfs.iso");
    context.builder.getInstallStep().dependOn(&context.install_disk_image.step);
}
