pub const Id = 3;
const scheduler = @import("../task/scheduler.zig");
const signal = @import("../task/signal.zig");

pub fn do(id: signal.Id) !void {
    signal.kill(scheduler.get_current_task().pid, id) catch @panic("todo");
}
