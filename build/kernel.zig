const std = @import("std");
const CrossTarget = @import("std").zig.CrossTarget;
const Feature = @import("std").Target.Cpu.Feature;
const Builder = @import("std").build.Builder;
const Step = @import("std").build.Step;
const Target = @import("std").Target;
const BuildContext = @import("../build.zig").BuildContext;

pub fn build_executable(context: *BuildContext) void {
    var cpu_features_sub: Feature.Set = Feature.Set.empty;
    cpu_features_sub.addFeature(@intFromEnum(Target.x86.Feature.mmx));
    cpu_features_sub.addFeature(@intFromEnum(Target.x86.Feature.sse));
    cpu_features_sub.addFeature(@intFromEnum(Target.x86.Feature.sse2));
    cpu_features_sub.addFeature(@intFromEnum(Target.x86.Feature.avx));
    cpu_features_sub.addFeature(@intFromEnum(Target.x86.Feature.avx2));

    context.kernel = context.builder.addExecutable(.{
        .name = context.name,
        .root_source_file = .{ .cwd_relative = "src/boot.zig" },
        .target = context.builder.resolveTargetQuery(CrossTarget{
            .cpu_arch = Target.Cpu.Arch.x86,
            .os_tag = Target.Os.Tag.freestanding,
            .abi = Target.Abi.none,
            .cpu_features_sub = cpu_features_sub,
        }),
        .optimize = context.optimize,
    });

    context.build_options = context.builder.addOptions();
    context.build_options.addOption(bool, "posix", context.posix);
    context.build_options.addOption(std.builtin.OptimizeMode, "optimize", context.optimize);
    context.build_options.addOption(bool, "ci", context.ci);
    context.kernel.root_module.addOptions("build_options", context.build_options);

    const colors_module = context.builder.createModule(
        .{ .root_source_file = .{ .cwd_relative = "./src/misc/colors.zig" } },
    );
    context.kernel.root_module.addImport("colors", colors_module);

    context.kernel.addIncludePath(std.Build.LazyPath{ .cwd_relative = "./src/c_headers/" });

    context.kernel.setLinkerScriptPath(.{ .cwd_relative = "src/linker.ld" });
    context.kernel.entry = .{ .symbol_name = "_entry" };

    context.install_kernel = context.builder.addInstallArtifact(context.kernel, .{
        .dest_dir = .{ .override = .{ .custom = "iso/boot/bin" } },
    });
}
