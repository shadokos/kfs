const memory = @import("../memory.zig");
const paging = @import("../memory/paging.zig");
const VirtualSpace = @import("../memory/virtual_space.zig");
const cpu = @import("../cpu.zig");
const task_set = @import("task_set.zig");
const signal = @import("signal.zig");
const Cache = @import("../memory/object_allocators/slab/cache.zig").Cache;
const scheduler = @import("scheduler.zig");
const status_informations = @import("status_informations.zig");
const StatusStack = @import("status_stack.zig").StatusStack;
const logger = @import("../ft/ft.zig").log.scoped(.task);
const Errno = @import("../errno.zig").Errno;

pub const TaskDescriptor = struct {
    stack: [4096]u8 align(4096) = undefined, // todo
    pid: Pid,
    pgid: Pid,

    state: State,

    parent: ?*TaskDescriptor,
    childs: ?*TaskDescriptor = null,
    next_sibling: ?*TaskDescriptor = null,

    status_info: ?status_informations.Status = null,
    status_stack: StatusStack = .{},
    status_stack_process_node: StatusStack.Node = .{},
    // status_stack_group_node : StatusStack.Node = .{},

    esp: u32 = undefined,

    // scheduling
    prev: *TaskDescriptor = undefined,
    next: *TaskDescriptor = undefined,

    pub const State = enum(u8) {
        Running,
        Zombie,
    };
    pub const Pid = i32;
    pub const Self = @This();

    pub var cache: *Cache = undefined;

    pub fn init_cache() !void {
        cache = try memory.globalCache.create(
            "task_descriptor",
            memory.directPageAllocator.page_allocator(),
            @sizeOf(Self),
            @alignOf(Self),
            6,
        );
    }

    pub fn deinit(self: *Self) void {
        if (self.parent) |p| {
            p.status_stack.remove(&self.status_stack_process_node);
            var n: ?*Self = p.childs;
            if (n == self) {
                p.childs = self.next_sibling;
            }
            while (n) |nv| : (n = nv.next_sibling) {
                if (nv.next_sibling == self) {
                    break;
                }
            }
            if (n) |prev| {
                prev.next_sibling = self.next_sibling;
            }
        }
        // todo: process group status_stack
        while (self.childs) |c| {
            task_set.destroy_task(c.pid) catch @panic("cannot deinit task");
        }
    }

    pub fn update_status(self: *Self, new_status_info: ?status_informations.Status) void {
        self.status_info = new_status_info;
        if (new_status_info) |s| {
            if (self.parent) |p| {
                p.status_stack.add(&self.status_stack_process_node, s.transition);
            }
            // todo: process group
        } else @panic("todo");
    }

    pub fn get_status(self: *Self) ?status_informations.Status {
        const ret = self.status_info;
        self.status_info = null;
        if (self.parent) |p| {
            p.status_stack.remove(&self.status_stack_process_node);
        }
        // todo: process group
        return ret;
    }

    pub fn autowait(self: *Self, transition: status_informations.Status.Transition) Errno!?*Self {
        if (self.status_info) |s| {
            if (s.transition != transition) {
                return null;
            }
            return self;
        } else return null;
    }

    pub fn wait_child(self: *Self, transition: status_informations.Status.Transition) Errno!?*Self {
        if (self.status_stack.top(transition)) |n| {
            const descriptor: *Self = @alignCast(@fieldParentPtr("status_stack_process_node", n));
            return descriptor;
        } else return null;
    }
};

pub noinline fn switch_to_task_opts(prev: *TaskDescriptor, next: *TaskDescriptor) void {
    asm volatile ("pushal");
    asm volatile (
        \\push %[lock_count]
        :
        : [lock_count] "r" (scheduler.lock_count),
    );

    prev.esp = cpu.get_esp();
    cpu.set_esp(next.esp);

    scheduler.lock_count = asm volatile (
        \\pop %eax
        : [_] "={eax}" (-> u32),
    );
    asm volatile ("popal");
}

pub fn switch_to_task(prev: *TaskDescriptor, next: *TaskDescriptor) void {
    scheduler.lock();
    defer scheduler.unlock();
    return switch_to_task_opts(prev, next);
}

pub fn getpid() TaskDescriptor.Pid {
    return scheduler.get_current_task().pid;
}

pub fn exit(code: u8) noreturn {
    scheduler.lock();

    const task = scheduler.get_current_task();
    task.state = .Zombie;
    task.update_status(.{
        .transition = .Terminated,
        .signaled = false,
        .siginfo = .{
            .si_status = code,
        },
    });

    scheduler.schedule();
    unreachable;
}

pub noinline fn start_task(function: *const fn () u8) noreturn {
    scheduler.unlock();
    exit(function());
}

pub fn spawn(function: *const fn () u8) !*TaskDescriptor {
    scheduler.lock();
    const descriptor = try task_set.create_task();
    var is_parent: bool = false;
    const is_parent_ptr: *volatile bool = &is_parent;
    scheduler.checkpoint();
    if (!is_parent_ptr.*) {
        is_parent_ptr.* = true;
        scheduler.set_current_task(descriptor);
        cpu.set_esp(@as(usize, @intFromPtr(&descriptor.stack)) + descriptor.stack.len);
        start_task(function);
    }
    scheduler.unlock();
    return descriptor;
}