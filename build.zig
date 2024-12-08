const std = @import("std");
const Step = @import("std").Build.Step;
const Builder = @import("std").Build;

pub const BuildContext = struct {
    builder: *Builder,
    optimize: std.builtin.Mode = undefined,
    iso_source_dir: []const u8 = undefined,
    name: []const u8 = undefined,
    bootloader: enum { grub, limine } = .grub,
    posix: bool = false,
    ci: bool = false,
};

pub fn build(b: *Builder) !void {
    var context = BuildContext{ .builder = b };

    context.iso_source_dir = b.option(
        []const u8,
        "iso_dir",
        "Specify the iso directory source",
    ) orelse "iso";

    context.name = b.option(
        []const u8,
        "name",
        "Specify a name for output binary",
    ) orelse "kfs.elf";

    context.posix = b.option(
        bool,
        "posix",
        "Enable this flag if strict POSIX conformance is wanted",
    ) orelse false;

    context.bootloader = b.option(
        @TypeOf(context.bootloader),
        "bootloader",
        "Specify the bootloader to use",
    ) orelse .grub;

    context.ci = b.option(bool, "ci", "Build the kernel for CI") orelse false;

    context.optimize = b.standardOptimizeOption(.{});

    // Build steps
    const kernel = @import("build/kernel.zig").build_executable(&context);
    const themes = @import("build/themes.zig").install_themes(&context);
    const install_disk_image = @import("build/iso.zig").build_iso(&context, kernel);
    const uninstall_themes = @import("build/themes.zig").uninstall_themes(&context);
    _ = @import("build/qemu.zig").add_step_run(&context, install_disk_image);

    // Dependencies
    kernel.step.dependOn(&themes.step);
    b.getInstallStep().dependOn(&install_disk_image.step);
    b.getUninstallStep().dependOn(&uninstall_themes.step);
}
