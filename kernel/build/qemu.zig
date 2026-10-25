const std = @import("std");
const Step = @import("std").Build.Step;

const BuildContext = @import("../build.zig").BuildContext;

pub fn add_step_run(context: *BuildContext, install_disk_image: *Step.InstallFile) *Step {
    const qemu = context.builder.addSystemCommand(&.{ "qemu-system-i386", "-cdrom" });

    qemu.addFileArg(install_disk_image.source);

    const run = context.builder.step("run", "Run kfs with qemu");
    run.dependOn(&qemu.step);

    return run;
}
