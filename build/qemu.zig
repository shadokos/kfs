const std = @import("std");

const BuildContext = @import("../build.zig").BuildContext;

pub fn add_step_run(context: *BuildContext) void {
    context.qemu = context.builder.addSystemCommand(&.{ "qemu-system-i386", "-cdrom" });
    context.qemu.addFileArg(context.install_disk_image.source);
    context.run = context.builder.step("run", "Run kfs with qemu");
    context.run.dependOn(&context.qemu.step);
}
