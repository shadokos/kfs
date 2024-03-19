const std = @import("std");
const Builder = @import("std").build.Builder;
const Target = @import("std").Target;
const Feature = @import("std").Target.Cpu.Feature;
const CrossTarget = @import("std").zig.CrossTarget;

pub fn build(b: *Builder) void {
    const name = b.option([]const u8, "name", "Specify a name for output binary") orelse "kernel.elf";
    const posix = b.option(bool, "posix", "Enable this flag if strict POSIX conformance is wanted") orelse false;

    var cpu_features_sub: Feature.Set = Feature.Set.empty;

    const features = Target.x86.Feature;
    cpu_features_sub.addFeature(@intFromEnum(features.mmx));
    cpu_features_sub.addFeature(@intFromEnum(features.sse));
    cpu_features_sub.addFeature(@intFromEnum(features.sse2));
    cpu_features_sub.addFeature(@intFromEnum(features.avx));
    cpu_features_sub.addFeature(@intFromEnum(features.avx2));

    const target = CrossTarget{
        .cpu_arch = Target.Cpu.Arch.x86,
        .os_tag = Target.Os.Tag.freestanding,
        .abi = Target.Abi.none,
        .cpu_features_sub = cpu_features_sub,
    };

    const kernel = b.addExecutable(.{
        .name = name,
        .root_source_file = .{ .path = "src/boot.zig" },
        .target = target,
        .optimize = b.standardOptimizeOption(.{}),
    });

    const build_options = b.addOptions();
    build_options.addOption(bool, "posix", posix);
    build_options.addOption(std.builtin.OptimizeMode, "optimize", kernel.optimize);
    kernel.addOptions("build_options", build_options);

    const colors_module = b.createModule(.{ .source_file = .{ .path = "./src/misc/colors.zig" } });
    kernel.addModule("colors", colors_module);

    kernel.addIncludePath(std.Build.LazyPath{ .path = "./src/c_headers/" });

    kernel.setLinkerScriptPath(.{ .path = "src/linker.ld" });
    b.installArtifact(kernel);
}
