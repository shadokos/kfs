const std = @import("std");
const Step = @import("std").Build.Step;

const BuildContext = @import("../../build.zig").BuildContext;
const addDirectoryDependency = @import("../Step/DirectoryDependency.zig").addDirectoryDependency;

pub fn register_uninstall(context: *BuildContext) *Step.Run {
    const limine_uninstall = context.builder.addSystemCommand(&.{
        "make",
        "-f",
        "build/Makefiles/Limine.mk",
        "limine_clean",
        "--no-print-directory",
    });

    limine_uninstall.setName("uninstall limine");
    return limine_uninstall;
}

pub fn install(context: *BuildContext) *Step.Run {
    const limine_install = context.builder.addSystemCommand(&.{
        "make",
        "-f",
        "build/Makefiles/Limine.mk",
        "limine",
        "--no-print-directory",
    });
    limine_install.setName("install limine");
    return limine_install;
}

pub fn install_iso_folder(context: *BuildContext) *Step.InstallDir {
    const limine_install = install(context);

    const install_iso = context.builder.addInstallDirectory(.{
        .source_dir = .{ .cwd_relative = context.iso_source_dir },
        .install_dir = .prefix,
        .install_subdir = "iso",
    });

    const limine_bios_sys: *Step.InstallFile = context.builder.addInstallFileWithDir(
        .{ .cwd_relative = "limine/limine-bios.sys" },
        .{ .custom = "iso/boot/" },
        "limine-bios.sys",
    );
    limine_bios_sys.step.dependOn(&limine_install.step);

    const limine_bios_cd: *Step.InstallFile = context.builder.addInstallFileWithDir(
        .{ .cwd_relative = "limine/limine-bios-cd.bin" },
        .{ .custom = "iso/boot/" },
        "limine-bios-cd.bin",
    );
    limine_bios_cd.step.dependOn(&limine_install.step);

    const limine_uefi_cd: *Step.InstallFile = context.builder.addInstallFileWithDir(
        .{ .cwd_relative = "limine/limine-uefi-cd.bin" },
        .{ .custom = "iso/boot/" },
        "limine-uefi-cd.bin",
    );
    limine_uefi_cd.step.dependOn(&limine_install.step);

    const limine_bootia32: *Step.InstallFile = context.builder.addInstallFileWithDir(
        .{ .cwd_relative = "limine/BOOTIA32.EFI" },
        .{ .custom = "iso/boot/" },
        "EFI/Boot/BOOTIA32.EFI",
    );
    limine_bootia32.step.dependOn(&limine_install.step);

    install_iso.step.dependOn(&limine_bios_sys.step);
    install_iso.step.dependOn(&limine_bios_cd.step);
    install_iso.step.dependOn(&limine_uefi_cd.step);
    install_iso.step.dependOn(&limine_bootia32.step);

    return install_iso;
}

pub fn build_disk_image(context: *BuildContext, install_kernel: *Step.InstallArtifact) *Step.InstallFile {
    const install_iso_path = context.builder.pathResolve(&.{ context.builder.install_prefix, "iso" });

    const xorriso = context.builder.addSystemCommand(&.{
        "xorriso",
        "-as",
        "mkisofs",
        "-R",
        "-r",
        "-J",
        "-b",
        "boot/limine-bios-cd.bin",
        "-no-emul-boot",
        "-boot-load-size",
        "4",
        "-boot-info-table",
        "-hfsplus",
        "-apm-block-size",
        "2048",
        "--efi-boot",
        "boot/limine-uefi-cd.bin",
        "-efi-boot-part",
        "--efi-boot-image",
        "--protective-msdos-label",
        "-o",
    });
    const iso_file = xorriso.addOutputFileArg("kfs.iso");
    _ = xorriso.addDirectoryArg(.{ .cwd_relative = install_iso_path });

    const directory_step = addDirectoryDependency(
        xorriso,
        .{ .cwd_relative = install_iso_path },
    );

    directory_step.step.dependOn(&install_iso_folder(context).step);
    directory_step.step.dependOn(&install_kernel.step);

    const bios_install: *Step.Run = context.builder.addSystemCommand(&.{
        "./limine/limine",
        "bios-install",
    });
    bios_install.addFileArg(iso_file);

    const install_disk_image = context.builder.addInstallFile(iso_file, "../kfs.iso");
    install_disk_image.step.dependOn(&bios_install.step);
    return install_disk_image;
}
