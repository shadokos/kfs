const std = @import("std");
const Builder = @import("std").build.Builder;
const Target = @import("std").Target;
const CrossTarget = @import("std").zig.CrossTarget;
 
pub fn build(b: *Builder) void {
	const name = b.option([]const u8, "name", "Specify a name for output binary") orelse "kernel.elf";

	const target = CrossTarget {
		.cpu_arch = Target.Cpu.Arch.x86,
		.os_tag = Target.Os.Tag.freestanding,
		.abi = Target.Abi.none,
	};

	const kernel = b.addExecutable(.{
		.name = name,
		.root_source_file = .{ .path = "src/boot.zig" },
		.target = target,
		.optimize = b.standardOptimizeOption(.{})
	});

	kernel.setLinkerScriptPath(.{ .path = "src/linker.ld" });
	b.installArtifact(kernel);
}
