const ft = @import("ft");
const memory = @import("../memory.zig");
const interrupts = @import("../interrupts.zig");
const paging = @import("../memory/paging.zig");
const VirtualSpace = @import("../memory/virtual_space.zig").VirtualSpace;
const cpu = @import("../cpu.zig");
const gdt = @import("../gdt.zig");
const task_set = @import("task_set.zig");
const signal = @import("signal.zig");
const ucontext = @import("ucontext.zig");
const Cache = @import("../memory/object_allocators/slab/cache.zig").Cache;
const scheduler = @import("scheduler.zig");
const ready_queue = @import("ready_queue.zig");
const wait_queue = @import("wait_queue.zig");
const status_informations = @import("status_informations.zig");
const StatusStack = @import("status_stack.zig").StatusStack;
const logger = ft.log.scoped(.task);
const Errno = @import("../errno.zig").Errno;

pub const TaskDescriptor = struct {
    // todo: define the appropriate size for a kernelspace stack or get this value from config
    stack: [64 * 1024]u8 align(4096) = undefined,
    pid: Pid,
    pgid: Pid,

    owner: u32 = 0,

    state: State,

    parent: ?*TaskDescriptor,
    childs: ?*TaskDescriptor = null,
    next_sibling: ?*TaskDescriptor = null,

    vm: ?*VirtualSpace = null,

    status_wait_queue: @import("wait.zig").WaitQueue = .{},
    status_info: ?status_informations.Status = null,
    status_stack: StatusStack = .{},
    status_stack_process_node: StatusStack.Node = .{},
    // status_stack_group_node : StatusStack.Node = .{},

    signalManager: signal.SignalManager = signal.SignalManager.init(),

    esp: u32 = undefined,

    ucontext: ucontext.ucontext_t = .{},

    // scheduling
    rq_node: ready_queue.Node = .{ .data = false },
    wq_node: wait_queue.Node = .{ .data = undefined },

    pub const State = enum(u8) {
        Running,
        Blocked,
        BlockedUninterruptible,
        Ready,
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
        self.status_wait_queue.unblock_all();
        wait_queue.force_remove(self);

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

        if (self.vm) |vm| {
            vm.deinit();
            VirtualSpace.cache.allocator().destroy(vm);
            self.vm = null;
        }

        // todo: process group status_stack
        // todo: this is unbounded recursivity
        while (self.childs) |c| {
            task_set.destroy_task(c.pid) catch @panic("cannot deinit task");
        }
    }

    pub fn update_status(self: *Self, new_status_info: ?status_informations.Status) void {
        self.status_info = new_status_info;
        if (new_status_info) |s| {
            if (self.parent) |p| {
                p.status_stack.add(&self.status_stack_process_node, s.transition);
                p.status_wait_queue.try_unblock();
            }
            // todo: process group
        } else @panic("todo");
    }

    pub fn init_vm(self: *Self) !void {
        if (self.vm != null) {
            @panic("task already has a vm");
        }
        const vm = try VirtualSpace.cache.allocator().create(VirtualSpace);
        try vm.init();
        try vm.add_space(0, paging.high_half / paging.page_size);
        try vm.add_space((paging.page_tables) / paging.page_size, 768);
        vm.transfer();
        try vm.fill_page_tables(paging.page_tables / paging.page_size, 768, false);
        self.vm = vm;
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

    pub fn autowait(self: *Self, mask: status_informations.Status.TransitionMask) ?*Self {
        if (self.status_info) |s| {
            if (!mask.check(s.transition)) {
                return null;
            }
            return self;
        } else return null;
    }

    pub fn wait_child(self: *Self, mask: status_informations.Status.TransitionMask) ?*Self {
        if (self.status_stack.top(mask)) |n| {
            const descriptor: *Self = @alignCast(@fieldParentPtr("status_stack_process_node", n));
            return descriptor;
        } else return null;
    }

    fn handle_default_action(self: *Self, sig: signal.siginfo_t) void {
        switch (self.signalManager.get_defaultAction(sig.si_signo.unwrap())) {
            .Ignore => {},
            .Terminate => {
                if (self.state == .Ready)
                    ready_queue.remove(self);
                self.state = .Zombie;
                self.update_status(.{
                    .transition = .Terminated,
                    .signaled = true,
                    .siginfo = sig,
                });
            },
            .Stop => if (self.state == .Running or self.state == .Ready) {
                if (self.state == .Ready)
                    ready_queue.remove(self);
                self.state = .Stopped;
                self.update_status(.{
                    .transition = .Stopped,
                    .signaled = true,
                    .siginfo = sig,
                });
            },
            .Continue => if (self.state == .Stopped) {
                self.update_status(.{
                    .transition = .Continued,
                    .signaled = true,
                    .siginfo = sig,
                });
            },
        }
    }

    fn add_signal_frame(self: *Self, action: signal.Sigaction, info: signal.siginfo_t) void {
        // push ucontext on stack
        self.ucontext.uc_link = ucontext.put_on_stack(&self.ucontext, self.ucontext);

        // put trampoline on stack
        const rfi_sigreturn: [*]u8 = @extern([*]u8, .{ .name = "_rfi_sigreturn" });
        const rfi_sigreturn_end: [*]u8 = @extern([*]u8, .{ .name = "_rfi_sigreturn_end" });

        const bytecode = rfi_sigreturn[0 .. @as(usize, @intFromPtr(rfi_sigreturn_end)) - @as(
            usize,
            @intFromPtr(rfi_sigreturn),
        )];
        const bytecode_begin = ucontext.put_data_on_stack(&self.ucontext, bytecode).ptr;

        if (!action.sa_flags.SA_NODEFER) {
            self.ucontext.uc_sigmask |=
                @as(signal.SigSet, 1) << @as(u5, @intCast(@intFromEnum(info.si_signo.unwrap())));
        }

        self.ucontext.uc_sigmask |= action.sa_mask;

        if (action.sa_flags.SA_SIGINFO) {
            const siginfo_address = ucontext.put_on_stack(&self.ucontext, info);
            ucontext.makecontext(
                &self.ucontext,
                @intFromPtr(bytecode_begin),
                @intFromPtr(action.sa_sigaction),
                .{ info.si_signo, siginfo_address, self.ucontext.uc_link },
            );
        } else {
            ucontext.makecontext(
                &self.ucontext,
                @intFromPtr(bytecode_begin),
                @intFromPtr(action.sa_handler),
                .{info.si_signo},
            );
        }
    }

    pub fn do_action(self: *Self, action: signal.Sigaction, info: signal.siginfo_t) void {
        if (action.sa_flags.SA_SIGINFO) {
            self.add_signal_frame(action, info);
        } else if (action.sa_handler == signal.SIG_DFL) {
            self.handle_default_action(info);
        } else if (action.sa_handler != signal.SIG_IGN) {
            self.add_signal_frame(action, info);
        }
    }

    pub fn handle_signal(self: *Self) void {
        while (self.signalManager.get_pending_signal(self.ucontext.uc_sigmask)) |info| {
            const id: signal.Id = info.si_signo.unwrap();
            const action = self.signalManager.get_action(id);
            self.do_action(action, info);
        }
    }

    pub fn send_signal(self: *Self, sig: signal.siginfo_t) void {
        self.signalManager.queue_signal(sig);
        if (sig.si_signo.safeUnwrap() == .SIGCONT and self.state == .Stopped) {
            self.state = .Ready;
            ready_queue.push(self);
        } else if (self.state == .Blocked) {
            @import("wait_queue.zig").interrupt(self);
        }
    }

    pub noinline fn spawn(self: *Self, function: *const fn (usize) u8, data: usize) !void {
        scheduler.lock();
        var is_parent: u8 = 0;
        asm volatile (
            \\ movb $0, (%[is_parent])
            \\ push %[function]
            \\ push %[data]
            \\ push %[new_stack]
            \\ push %[is_parent]
            \\ push %[self]
            \\ call checkpoint
            \\ pop %[self]
            \\ pop %[is_parent]
            \\ pop %[new_stack]
            \\ pop %[data]
            \\ pop %[function]
            \\ movb (%[is_parent]), %[tmp:b]
            \\ cmpb $0, %[tmp:b]
            \\ jne child
            \\ parent:
            \\ movb $1, (%[is_parent])
            \\ mov %[new_stack], %esp
            \\ push %[data]
            \\ push %[function]
            \\ push %[self]
            \\ call start_task
            \\ child:
            :
            : [function] "r" (function),
              [data] "r" (data),
              [is_parent] "r" (&is_parent),
              [new_stack] "r" (@as(usize, @intFromPtr(&self.stack)) + self.stack.len),
              [self] "r" (self),
              [tmp] "q" (0),
        );
        scheduler.unlock();
    }

    pub export fn start_task(self: *Self, function_ptr: *void, data: usize) callconv(.C) noreturn {
        const function: *const fn (usize) u8 = @ptrCast(function_ptr);
        self.state = .Running;
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

    if (prev.state == .Running) {
        ready_queue.push(prev);
    }
    next.state = .Running;

    gdt.tss.esp0 = @as(usize, @intFromPtr(&next.stack)) + next.stack.len;
    gdt.flush();

    return switch_to_task_opts(prev, next);
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

    ready_queue.remove(task);

    scheduler.schedule();
    unreachable;
}
