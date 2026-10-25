const scheduler = @import("../task/scheduler.zig");
const signal = @import("../task/signal.zig");

pub const Id = 11;

pub fn do(id: signal.Id, act: ?*signal.Sigaction, oldact: ?*signal.Sigaction) !void {
    if (oldact) |oldact_ptr| {
        oldact_ptr.* = scheduler.get_current_task().signalManager.get_action(id);
    }
    if (act) |act_ptr| {
        scheduler.get_current_task().signalManager.change_action(id, act_ptr.*) catch @panic("todo");
    }
}
