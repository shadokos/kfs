const std = @import("std");
const Step = @import("std").Build.Step;

const BuildContext = @import("../build.zig").BuildContext;

pub fn build_iso(context: *BuildContext, kernel: *Step.InstallArtifact) *Step.InstallFile {
    return switch (context.bootloader) {
        .grub => b: {
            break :b @import("bootloaders/grub.zig").build_disk_image(context, kernel);
        },
        .limine => b: {
            const limine = @import("bootloaders/limine.zig");
            context.builder.getUninstallStep().dependOn(&limine.register_uninstall(context).step);
            break :b limine.build_disk_image(context, kernel);
        },
    };
}
