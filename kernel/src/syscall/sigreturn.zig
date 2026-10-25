const interrupt = @import("../interrupts.zig");
const InterruptFrame = interrupt.InterruptFrame;

pub const Id = 4;

pub fn do_raw() void {
    const task = @import("../task/scheduler.zig").get_current_task();
    // todo: prevent the petit malins from altering the frame and changing the segments.
    if (task.ucontext.uc_link) |old| {
        task.ucontext = old.*;
    }
}
