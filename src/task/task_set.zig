const ft = @import("../ft/ft.zig");
const task = @import("task.zig");
const TaskDescriptor = task.TaskDescriptor;
const scheduler = @import("scheduler.zig");

const NTASK = 100; // todo

var list: [NTASK]?*TaskDescriptor = [1]?*TaskDescriptor{null} ** NTASK;
var head: TaskDescriptor.Pid = 0;
var count: usize = 0;

pub fn create_task() !*TaskDescriptor {
    scheduler.lock();
    defer scheduler.unlock();

    const pid = next_pid() orelse return error.TooMuchProcesses;
    const new_task = try TaskDescriptor.cache.allocator().create(TaskDescriptor);
    const parent = scheduler.get_current_task();
    if (pid == 0) {
        new_task.* = .{ .pid = pid, .pgid = pid, .parent = null, .state = .Running };
        scheduler.init(new_task);
    } else {
        new_task.* = .{ .pid = pid, .pgid = parent.pgid, .parent = parent, .state = .Running };
        new_task.next_sibling = parent.childs;
        parent.childs = new_task;
        scheduler.add_task(new_task);
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
    if (pid < 0) return null;
    return list[@intCast(pid)];
}

pub fn destroy_task(pid: TaskDescriptor.Pid) !void {
    scheduler.lock();
    defer scheduler.unlock();

    if (pid < 0) return error.NoSuchTask;
    const index: u32 = @intCast(pid);
    const descriptor = list[index] orelse return error.NoSuchTask; // todo error
    scheduler.remove_task(descriptor);
    descriptor.deinit();
    list[index] = null;
    count -= 1;
    TaskDescriptor.cache.allocator().destroy(descriptor);
}