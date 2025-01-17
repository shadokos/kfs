const memory = @import("../memory.zig");
const paging = @import("../memory/paging.zig");
const VirtualSpace = @import("../memory/virtual_space.zig").VirtualSpace;
const cpu = @import("../cpu.zig");
const gdt = @import("../gdt.zig");
const task_set = @import("task_set.zig");
const signal = @import("signal.zig");
const Cache = @import("../memory/object_allocators/slab/cache.zig").Cache;
const scheduler = @import("scheduler.zig");
const status_informations = @import("status_informations.zig");
const StatusStack = @import("status_stack.zig").StatusStack;
const logger = @import("ft").log.scoped(.task);
const Errno = @import("../errno.zig").Errno;

pub const TaskDescriptor = struct {
    stack: [16 * 1024]u8 align(4096) = undefined, // todo
    pid: Pid,
    pgid: Pid,

    state: State,

    parent: ?*TaskDescriptor,
    childs: ?*TaskDescriptor = null,
    next_sibling: ?*TaskDescriptor = null,

    vm: ?*VirtualSpace = null,

    status_info: ?status_informations.Status = null,
    status_stack: StatusStack = .{},
    status_stack_process_node: StatusStack.Node = .{},
    // status_stack_group_node : StatusStack.Node = .{},

    signalManager: signal.SignalManager = signal.SignalManager.init(),

    esp: u32 = undefined,

    // scheduling
    prev: *TaskDescriptor = undefined,
    next: *TaskDescriptor = undefined,

    pub const State = enum(u8) {
        Running,
        Stopped,
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
        if (self.vm) |_| {
            // todo destroy vm
        }
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

    pub fn clone_vm(self: *Self, other: *Self) !void {
        if (self.vm != null) {
            @panic("task already has a vm");
        }
        if (other.vm) |vm| {
            self.vm = try vm.clone();
        }
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

    pub fn handle_signal(self: *Self) void {
        while (self.signalManager.get_pending_signal_for_handler(signal.SIG_DFL)) |sig| {
            switch (self.signalManager.get_defaultAction(@enumFromInt(sig.si_signo))) {
                .Ignore => {},
                .Terminate => {
                    self.state = .Zombie;
                    self.update_status(.{
                        .transition = .Terminated,
                        .signaled = true,
                        .siginfo = sig,
                    });
                    scheduler.schedule();
                    unreachable;
                },
                .Stop => if (self.state == .Running) {
                    self.state = .Stopped;
                    self.update_status(.{
                        .transition = .Stopped,
                        .signaled = true,
                        .siginfo = sig,
                    });
                },
                .Continue => if (self.state == .Stopped) {
                    self.state = .Running;
                    self.update_status(.{
                        .transition = .Continued,
                        .signaled = true,
                        .siginfo = sig,
                    });
                },
            }
        }
    }

    pub fn spawn(self: *Self, function: *const fn (anytype) u8, data: anytype) !void {
        scheduler.lock();
        var is_parent: bool = false;
        const is_parent_ptr: *volatile bool = &is_parent;
        scheduler.checkpoint();
        if (is_parent_ptr.*) {} else {
            is_parent_ptr.* = true;
            cpu.set_esp(@as(usize, @intFromPtr(&self.stack)) + self.stack.len);
            self.start_task(function, data);
        }
        scheduler.unlock();
    }

    pub noinline fn start_task(self: *Self, function: *const fn (anytype) u8, data: anytype) noreturn {
        scheduler.add_task(self);
        scheduler.set_current_task(self);
        gdt.tss.esp0 = @as(usize, @intFromPtr(&self.stack)) + self.stack.len;
        gdt.flush();
        scheduler.unlock();
        exit(function(data));
    }
};

pub noinline fn switch_to_task_opts(prev: *TaskDescriptor, next: *TaskDescriptor) void {
    asm volatile (
        \\ pushal
        \\ mov %cr3, %eax
        \\ push %eax
    );
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
    asm volatile (
        \\ pop %eax
        \\ mov %eax, %cr3
        \\ popal
    );
}

pub fn switch_to_task(prev: *TaskDescriptor, next: *TaskDescriptor) void {
    scheduler.lock();
    defer scheduler.unlock();
    gdt.tss.esp0 = @as(usize, @intFromPtr(&next.stack)) + next.stack.len;
    gdt.flush();
    switch_to_task_opts(prev, next);
}

pub fn init_vm(t: *TaskDescriptor) !void {
    if (t.vm) |_| {
        return;
    }
    t.vm = try VirtualSpace.cache.allocator().create(VirtualSpace);
    if (t.vm) |vm| {
        try vm.init();
        try vm.add_space(0, paging.high_half / paging.page_size);
        try vm.add_space((paging.page_tables) / paging.page_size, 768);
        vm.transfer();
        try vm.fill_page_tables(paging.page_tables / paging.page_size, 768, false);
    } else unreachable;
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
