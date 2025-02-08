const scheduler = @import("../task/scheduler.zig");
const signal = @import("../task/signal.zig");

pub const Id = 8;

pub fn do(id: signal.Id, handler: signal.Handler) !void {
    scheduler.get_current_task().signalManager.change_action(id, .{ .sa_handler = handler }) catch @panic("todo");
}
