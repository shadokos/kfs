const ft = @import("../ft/ft.zig");
const task = @import("task.zig");
const TaskDescriptor = task.TaskDescriptor;

const NTASK = 100; // todo

var list: [NTASK]?*TaskDescriptor = [1]?*TaskDescriptor{null} ** NTASK;
var head: TaskDescriptor.Pid = 0;
var count: usize = 0;

pub fn create_task() !*TaskDescriptor {
    const pid = next_pid() orelse return error.TooMuchProcesses;
    const new_task = try task.TaskUnion.cache.allocator().create(task.TaskUnion);
    new_task.task = .{ .pid = pid };
    list[pid] = &new_task.task;
    count += 1;
    return &new_task.task;
}

fn next_pid() ?TaskDescriptor.Pid {
    if (count == NTASK) {
        return null;
    }
    while (list[head]) |_| {
        head += 1;
        if (head == NTASK) {
            head = 0;
        }
    }
    return head;
}

pub fn get_task_descriptor(pid: TaskDescriptor.Pid) ?*TaskDescriptor {
    return list[pid];
}

pub fn remove_task(pid: TaskDescriptor.Pid) !void {
    const descriptor = list[pid] orelse return error.NoSuchTask; // todo error
    list[pid] = null;
    count -= 1;
    task.TaskUnion.cache.allocator().destroy(descriptor);
}
