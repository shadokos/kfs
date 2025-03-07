const std = @import("std");

const BuildContext = @import("../build.zig").BuildContext;

const syscall_dir = "src/syscall";
const output_file_path = "src/syscall_table.zig";

fn build_syscall_table(step: *std.Build.Step, _: std.Build.Step.MakeOptions) anyerror!void {
    var output_file = try std.fs.cwd().createFile(output_file_path, .{});
    defer output_file.close();

    var dir = std.fs.cwd().openDir(syscall_dir, .{ .iterate = true }) catch return;
    defer dir.close();

    var iter = try dir.walk(step.owner.allocator);
    defer iter.deinit();

    while (try iter.next()) |entry| {
        if (entry.kind != .file) continue;
        try output_file.writer().print("pub const {s} = @import(\"{s}/{s}\");\n", .{
            std.fs.path.stem(entry.basename), std.fs.path.basename(syscall_dir), entry.path,
        });
    }
}

pub fn build_syscall_table_step(context: *BuildContext) *std.Build.Step {
    const syscall_step = context.builder.allocator.create(std.Build.Step) catch @panic("OOM");
    syscall_step.* = std.Build.Step.init(.{
        .id = .custom,
        .name = "create syscall table",
        .owner = context.builder,
        .makeFn = build_syscall_table,
    });
    return syscall_step;
}

pub fn uninstall_syscall_table_step(context: *BuildContext) *std.Build.Step {
    const uninstall_theme = context.builder.addSystemCommand(&.{ "rm", output_file_path });
    uninstall_theme.setName("uninstall syscall table");
    return &uninstall_theme.step;
}
