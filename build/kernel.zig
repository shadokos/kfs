const std = @import("std");
const CrossTarget = @import("std").zig.CrossTarget;
const Feature = @import("std").Target.Cpu.Feature;
const Builder = @import("std").build.Builder;
const Step = @import("std").build.Step;
const Target = @import("std").Target;
const BuildContext = @import("../build.zig").BuildContext;

pub fn build_executable(context: *BuildContext, name: []const u8, posix: bool) void {
    var cpu_features_sub: Feature.Set = Feature.Set.empty;
    cpu_features_sub.addFeature(@intFromEnum(Target.x86.Feature.mmx));
    cpu_features_sub.addFeature(@intFromEnum(Target.x86.Feature.sse));
    cpu_features_sub.addFeature(@intFromEnum(Target.x86.Feature.sse2));
    cpu_features_sub.addFeature(@intFromEnum(Target.x86.Feature.avx));
    cpu_features_sub.addFeature(@intFromEnum(Target.x86.Feature.avx2));

    context.kernel = context.builder.addExecutable(.{
        .name = name,
        .root_source_file = .{ .path = "src/boot.zig" },
        .target = CrossTarget{
            .cpu_arch = Target.Cpu.Arch.x86,
            .os_tag = Target.Os.Tag.freestanding,
            .abi = Target.Abi.none,
            .cpu_features_sub = cpu_features_sub,
        },
        .optimize = context.builder.standardOptimizeOption(.{}),
    });

    context.build_options = context.builder.addOptions();
    context.build_options.addOption(bool, "posix", posix);
    context.build_options.addOption(std.builtin.OptimizeMode, "optimize", context.kernel.optimize);
    context.kernel.addOptions("build_options", context.build_options);

    const colors_module = context.builder.createModule(.{ .source_file = .{ .path = "./src/misc/colors.zig" } });
    context.kernel.addModule("colors", colors_module);

    context.kernel.addIncludePath(std.Build.LazyPath{ .path = "./src/c_headers/" });

    context.kernel.setLinkerScriptPath(.{ .path = "src/linker.ld" });

    context.install_kernel = context.builder.addInstallArtifact(context.kernel, .{
        .dest_dir = .{ .override = .{ .custom = "iso/boot/bin" } },
    });
}
