pub const Id = 20;
const Errno = @import("../errno.zig").Errno;
const scheduler = @import("../task/scheduler.zig");
const task = @import("../task/task.zig");
const paging = @import("../memory/paging.zig");

/// Set the userspace TLS base (mlibc TCB pointer) for the current task.
/// The base lands in the GDT TLS entry; userspace then addresses it
/// through %gs (selector index 9, RPL 3).
pub fn do(base: usize) !void {
    if (base == 0 or base >= paging.high_half)
        return Errno.EINVAL;
    const current_task = scheduler.get_current_task();
    current_task.tls_base = base;
    task.apply_tls(current_task);
}
