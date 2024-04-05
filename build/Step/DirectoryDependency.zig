const std = @import("std");

const AddDirectoryStep = struct {
    step: std.Build.Step,
    run_step: *std.Build.Step.Run,
    dir_path: std.Build.LazyPath,

    fn make(step: *std.Build.Step, _: *std.Progress.Node) !void {
        const self: *AddDirectoryStep = @alignCast(@fieldParentPtr(AddDirectoryStep, "step", step));
        const b = step.owner;

        const dir_path = self.dir_path.getPath(b);
        var dir = std.fs.cwd().openIterableDir(dir_path, .{}) catch return;
        defer dir.close();

        var iter = try dir.walk(b.allocator);
        defer iter.deinit();

        var filepaths = std.ArrayList([]const u8).init(b.allocator);
        defer filepaths.deinit();

        while (try iter.next()) |entry| {
            if (entry.kind != .file) continue;
            try filepaths.append(try std.fs.path.join(b.allocator, &.{ dir_path, entry.path }));
        }

        self.run_step.extra_file_dependencies = try filepaths.toOwnedSlice();
    }
};

pub fn addDirectoryDependency(
    run_step: *std.Build.Step.Run,
    dir_path: std.Build.LazyPath,
) *AddDirectoryStep {
    const owner = run_step.step.owner;
    const self = owner.allocator.create(AddDirectoryStep) catch @panic("OOM");
    self.* = .{
        .step = std.Build.Step.init(.{
            .id = .custom,
            .name = owner.fmt("Setting up recursive dependencies in {s}", .{dir_path.getDisplayName()}),
            .owner = owner,
            .makeFn = AddDirectoryStep.make,
        }),
        .run_step = run_step,
        .dir_path = dir_path,
    };

    run_step.step.dependOn(&self.step);
    return self;
}
