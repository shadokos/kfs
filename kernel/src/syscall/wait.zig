const wait = @import("../task/wait.zig");
const task = @import("../task/task.zig");
const Pid = task.TaskDescriptor.Pid;

pub const Id = 16;

pub fn do(stat_loc: ?*wait.Status) !Pid {
    return @import("waitpid.zig").do(-1, stat_loc, @bitCast(@as(i32, 0)));
}
