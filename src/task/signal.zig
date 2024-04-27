const ft = @import("../ft/ft.zig");
const task = @import("task.zig");
const TaskDescriptor = task.TaskDescriptor;
const scheduler = @import("scheduler.zig");
const task_set = @import("task_set.zig");
const paging = @import("../memory/paging.zig");

pub const siginfo_t = extern struct {
    si_signo: u32 = undefined,
    si_code: u32 = undefined,
    si_errno: u32 = undefined,
    si_pid: TaskDescriptor.Pid = undefined, // todo pid type
    // si_uid
    si_addr: paging.VirtualPtr = undefined,
    si_status: u32 = undefined,
    // si_value : sigval
};
