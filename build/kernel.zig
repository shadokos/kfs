const std = @import("std");
const CrossTarget = @import("std").zig.CrossTarget;
const Feature = @import("std").Target.Cpu.Feature;
const Builder = @import("std").build.Builder;
const Step = @import("std").Build.Step;
const Target = @import("std").Target;
const BuildContext = @import("../build.zig").BuildContext;

pub fn build_executable(context: *BuildContext) *Step.InstallArtifact {
    var cpu_features_sub: Feature.Set = Feature.Set.empty;
    cpu_features_sub.addFeature(@intFromEnum(Target.x86.Feature.mmx));
    cpu_features_sub.addFeature(@intFromEnum(Target.x86.Feature.sse));
    cpu_features_sub.addFeature(@intFromEnum(Target.x86.Feature.sse2));
    cpu_features_sub.addFeature(@intFromEnum(Target.x86.Feature.avx));
    cpu_features_sub.addFeature(@intFromEnum(Target.x86.Feature.avx2));

    const kernel = context.builder.addExecutable(.{
        .name = context.name,
        .root_source_file = .{ .cwd_relative = "src/boot.zig" },
        .target = context.builder.resolveTargetQuery(Target.Query{
            .cpu_arch = Target.Cpu.Arch.x86,
            .os_tag = Target.Os.Tag.freestanding,
            .abi = Target.Abi.none,
            .cpu_features_sub = cpu_features_sub,
        }),
        .optimize = context.optimize,
    });

    const build_options = context.builder.addOptions();
    build_options.addOption(bool, "posix", context.posix);
    build_options.addOption(std.builtin.OptimizeMode, "optimize", context.optimize);
    build_options.addOption(bool, "ci", context.ci);
    kernel.root_module.addOptions("build_options", build_options);

    const ft_module = context.builder.createModule(
        .{ .root_source_file = .{ .cwd_relative = "./src/ft/ft.zig" } },
    );
    const colors_module = context.builder.createModule(
        .{ .root_source_file = .{ .cwd_relative = "./src/misc/colors.zig" } },
    );
    const config_module = context.builder.createModule(
        .{ .root_source_file = .{ .cwd_relative = "./src/config.zig" } },
    );

    // Add "ft" and "config" module in colors_module
    colors_module.addImport("ft", ft_module);
    colors_module.addImport("config", config_module);

    // Add "ft" and "colors" module in config module
    config_module.addImport("ft", ft_module);
    config_module.addImport("colors", colors_module);

    // Add "ft, "colors" and "config" modules to the kernel
    kernel.root_module.addImport("ft", ft_module);
    kernel.root_module.addImport("colors", colors_module);
    kernel.root_module.addImport("config", config_module);

    kernel.addIncludePath(std.Build.LazyPath{ .cwd_relative = "./src/c_headers/" });

    kernel.setLinkerScript(.{ .cwd_relative = "src/linker.ld" });
    kernel.entry = .{ .symbol_name = "_entry" };

    return context.builder.addInstallArtifact(kernel, .{
        .dest_dir = .{ .override = .{ .custom = "iso/boot/bin" } },
    });
}
