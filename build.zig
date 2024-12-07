const std = @import("std");
const Step = @import("std").Build.Step;
const Builder = @import("std").Build;

pub const BuildContext = struct {
    builder: *Builder,
    build_options: *Step.Options = undefined,

    // Steps
    kernel: *Step.Compile = undefined,
    grub: *Step.Run = undefined,
    qemu: *Step.Run = undefined,
    run: *Step = undefined,

    // Installed files
    install_iso_folder: *Step.InstallDir = undefined,
    install_disk_image: *Step.InstallFile = undefined,
    install_kernel: *Step.InstallArtifact = undefined,

    // options
    optimize: std.builtin.Mode = undefined,
    iso_source_dir: []const u8 = undefined,
    name: []const u8 = undefined,
    bootloader: enum { grub, limine } = .grub,
    posix: bool = false,
    ci: bool = false,
};

pub fn build(b: *Builder) !void {
    var context = BuildContext{ .builder = b };

    context.iso_source_dir = context.builder.option(
        []const u8,
        "iso_dir",
        "Specify the iso directory source",
    ) orelse "iso";

    context.name = context.builder.option(
        []const u8,
        "name",
        "Specify a name for output binary",
    ) orelse "kfs.elf";

    context.posix = context.builder.option(
        bool,
        "posix",
        "Enable this flag if strict POSIX conformance is wanted",
    ) orelse false;

    context.bootloader = context.builder.option(
        @TypeOf(context.bootloader),
        "bootloader",
        "Specify the bootloader to use",
    ) orelse .grub;

    context.ci = b.option(bool, "ci", "Build the kernel for CI") orelse false;

    context.optimize = context.builder.standardOptimizeOption(.{});

    @import("std").debug.print("\x1b[32minstall prefix\x1b[0m: {s}\n", .{context.builder.install_prefix});
    @import("std").debug.print("\x1b[32minstall path\x1b[0m: {s}\n", .{context.builder.install_path});

    @import("build/kernel.zig").build_executable(&context);
    @import("build/themes.zig").install_themes(&context);
    switch (context.bootloader) {
        .grub => {
            @import("build/grub.zig").install_iso_folder(&context);
            @import("build/grub.zig").build_disk_image(&context);
        },
        .limine => {
            @import("build/limine.zig").install_iso_folder(&context);
            @import("build/limine.zig").build_disk_image(&context);
        },
    }
    @import("build/qemu.zig").add_step_run(&context);
}
