const std = @import("std");
const Builder = @import("std").Build;
const Target = @import("std").Target;
const Feature = @import("std").Target.Cpu.Feature;
const CrossTarget = @import("std").zig.CrossTarget;

pub fn build(b: *Builder) void {
    const name = b.option([]const u8, "name", "Specify a name for output binary") orelse "kernel.elf";
    const posix = b.option(bool, "posix", "Enable this flag if strict POSIX conformance is wanted") orelse false;
    const optimize = b.standardOptimizeOption(.{});

    var cpu_features_sub: Feature.Set = Feature.Set.empty;

    const features = Target.x86.Feature;
    cpu_features_sub.addFeature(@intFromEnum(features.mmx));
    cpu_features_sub.addFeature(@intFromEnum(features.sse));
    cpu_features_sub.addFeature(@intFromEnum(features.sse2));
    cpu_features_sub.addFeature(@intFromEnum(features.avx));
    cpu_features_sub.addFeature(@intFromEnum(features.avx2));

    const target = b.resolveTargetQuery(CrossTarget{
        .cpu_arch = Target.Cpu.Arch.x86,
        .os_tag = Target.Os.Tag.freestanding,
        .abi = Target.Abi.none,
        .cpu_features_sub = cpu_features_sub,
    });

    const kernel = b.addExecutable(.{
        .name = name,
        .root_source_file = .{ .path = "src/boot.zig" },
        .target = target,
        .optimize = optimize,
    });

    const build_options = b.addOptions();
    build_options.addOption(bool, "posix", posix);
    build_options.addOption(std.builtin.OptimizeMode, "optimize", optimize);
    kernel.root_module.addOptions("build_options", build_options);

    kernel.addIncludePath(std.Build.LazyPath{ .path = "./src/c_headers/" });
    kernel.entry = .{ .symbol_name = "_entry" };

    kernel.setLinkerScriptPath(.{ .path = "src/linker.ld" });
    b.installArtifact(kernel);
}
