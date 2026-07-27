const task = @import("task.zig");
const TaskDescriptor = task.TaskDescriptor;
const scheduler = @import("scheduler.zig");
const signal = @import("signal.zig");

const NTASK = 100; // todo: get this value from config

var list: [NTASK]?*TaskDescriptor = [1]?*TaskDescriptor{null} ** NTASK;
var head: TaskDescriptor.Pid = 0;
var count: usize = 0;

pub fn create_task() !*TaskDescriptor {
    scheduler.enter_critical();
    defer scheduler.exit_critical();

    const pid = next_pid() orelse return error.TooMuchProcesses;
    const new_task = try TaskDescriptor.cache.allocator().create(TaskDescriptor);
    const parent = scheduler.get_current_task();
    if (pid == 0) {
        new_task.* = .{ .pid = pid, .pgid = pid, .parent = null, .state = .Running };
    } else {
        new_task.* = .{
            .pid = pid,
            .pgid = parent.pgid,
            .parent = parent,
            .state = .Ready,
            .controlling_tty = parent.controlling_tty,
        };
        new_task.next_sibling = parent.childs;
        parent.childs = new_task;
    }
    list[@intCast(pid)] = new_task;
    count += 1;
    return new_task;
}

fn next_pid() ?TaskDescriptor.Pid {
    if (count == NTASK) {
        return null;
    }
    while (list[@intCast(head)]) |_| {
        head += 1;
        if (head == NTASK) {
            head = 0;
        }
    }
    return head;
}

pub fn get_task_descriptor(pid: TaskDescriptor.Pid) ?*TaskDescriptor {
    if (pid < 0 or pid >= list.len) return null;
    return list[@intCast(pid)];
}

/// Send `info` to every task of the process group `pgid`, and return how many
/// were signalled.
pub fn send_signal_to_group(pgid: TaskDescriptor.Pid, info: signal.siginfo_t) usize {
    scheduler.enter_critical();
    defer scheduler.exit_critical();

    var signalled: usize = 0;
    for (list) |entry| {
        const descriptor = entry orelse continue;
        if (descriptor.pgid != pgid) continue;
        descriptor.send_signal(info);
        signalled += 1;
    }
    return signalled;
}

pub fn destroy_task(pid: TaskDescriptor.Pid) !void {
    scheduler.enter_critical();
    defer scheduler.exit_critical();

    if (pid < 0) return error.NoSuchTask;
    const index: u32 = @intCast(pid);
    const descriptor = list[index] orelse return error.NoSuchTask; // todo error
    descriptor.deinit();
    list[index] = null;
    count -= 1;
    TaskDescriptor.cache.allocator().destroy(descriptor);
}
