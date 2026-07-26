const std = @import("std");
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
const logger = std.log.scoped(.task);
const Errno = @import("../errno.zig").Errno;
const vfs = @import("../fs/vfs.zig");
const TNode = @import("../fs/tnode.zig");
const FileSet = @import("file_set.zig");
const INode = @import("../fs/inode.zig");
const elf = @import("elf.zig");
const sysv = @import("sysv.zig");
const userspace = @import("userspace.zig");

const heapAlloc = memory.bigAlloc.allocator();
const smallAlloc = memory.smallAlloc.allocator();

const callback_allocator = @import("../memory.zig").smallAlloc.allocator();
const Callback = *const fn (*TaskDescriptor) void;
const Callbacks = std.ArrayList(Callback);

pub var on_terminate_callback: Callbacks = .empty;

pub fn add_on_terminate_callback(callback: *const fn (*TaskDescriptor) void) !void {
    try on_terminate_callback.append(callback_allocator, callback);
}

pub fn remove_on_terminate_callback(callback: *const fn (*TaskDescriptor) void) void {
    for (on_terminate_callback.items, 0..) |item, index| {
        if (item == callback) {
            on_terminate_callback.swapRemove(index);
            return;
        }
    }
}

pub const TaskDescriptor = struct {
    // todo: define the appropriate size for a kernelspace stack or get this value from config
    stack: [64 * 1024]u8 align(4096) = undefined,

    files: FileSet = .{},

    pid: Pid,
    pgid: Pid,

    /// Session this task belongs to, and through it the controlling terminal.
    /// Shared with every other task of the session, inherited across fork.
    session: *@import("session.zig"),

    owner: u32 = 0,
    cwd: *TNode,
    root: *TNode,

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

    /// Userspace TLS base (mlibc TCB), loaded into the GDT TLS entry and %gs.
    tls_base: ?u32 = null,

    ucontext: ucontext.ucontext_t = .{},

    // scheduling
    rq_node: ready_queue.QueueNode = .{ .data = false },
    wq_node: wait_queue.WaitQueueNode = .{ .data = undefined },

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
        self.session.release();

        // Hot fix;
        // When a task exits, the callback are called only for the parent task.
        // This behaviour leads to remaining child tasks in either waiting or running queues.
        // The hot fix ensures the callback are called for every tasks destroyed in any way.
        // Important note:
        // the callback can be called in both exit() and deinit() for a same task leading to some side effects.
        for (on_terminate_callback.items) |callback|
            callback(self);

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

        self.files.reset() catch {};

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

    /// POSIX 11.1.3: when the controlling process dies, its terminal leaves the
    /// session, so that another session leader can take it. The foreground
    /// group is hung up first, it was talking to a terminal it is about to lose.
    fn hangup_controlling_terminal(self: *Self) void {
        if (self.session.sid != self.pid) return;
        self.session.hangup();
    }

    /// What a blocking call should do about whatever signal is waiting.
    pub const Disposition = enum { none, stop, interrupt };

    pub fn pending_disposition(self: *Self) Disposition {
        const id = self.signalManager.peek_pending(self.ucontext.uc_sigmask) orelse return .none;
        // A handler runs, which is an interruption whatever the signal meant.
        if (self.signalManager.get_action(id).sa_handler != signal.SIG_DFL) return .interrupt;

        return switch (self.signalManager.get_defaultAction(id)) {
            .Stop => .stop,
            .Terminate => .interrupt,
            .Ignore, .Continue => .none,
        };
    }

    /// Stop on the caller's own stack rather than on the way out to userspace,
    /// so a blocking call resumes instead of returning short.
    pub fn stop_in_place(self: *Self) void {
        const info = self.signalManager.get_pending_signal(self.ucontext.uc_sigmask) orelse return;

        if (self.state == .Ready) ready_queue.remove(self);
        self.state = .Stopped;
        self.update_status(.{
            .transition = .Stopped,
            .signaled = true,
            .siginfo = info,
        });
        scheduler.schedule();
    }

    pub fn update_status(self: *Self, new_status_info: ?status_informations.Status) void {
        self.status_info = new_status_info;
        if (new_status_info) |s| {
            if (s.transition == .Terminated) self.hangup_controlling_terminal();
            if (self.parent) |p| {
                p.status_stack.add(&self.status_stack_process_node, s.transition);
                p.status_wait_queue.try_unblock();
            }
            // todo: process group
        } else @panic("todo");
    }

    fn deinit_vm(self: *Self) void {
        if (self.vm) |vm| {
            destroy_vm(vm);
            self.vm = null;
        }
    }

    fn destroy_vm(vm: *VirtualSpace) void {
        vm.deinit();
        VirtualSpace.cache.allocator().destroy(vm);
    }

    fn create_vm() !*VirtualSpace {
        const vm = try VirtualSpace.cache.allocator().create(VirtualSpace);
        try vm.init();
        try vm.add_space(0, paging.high_half / paging.page_size);
        try vm.add_space((paging.page_tables) / paging.page_size, 768);
        vm.transfer();
        try vm.fill_page_tables(paging.page_tables / paging.page_size, 768, false);
        return vm;
    }

    pub fn init_vm(self: *Self) !void {
        if (self.vm != null) {
            @panic("task already has a vm");
        }
        self.vm = try create_vm();
    }

    pub fn dupe_strings_z(strings: []const []const u8) Errno![]const [:0]const u8 {
        const out = smallAlloc.alloc([:0]const u8, strings.len) catch return Errno.ENOMEM;
        errdefer smallAlloc.free(out);
        var filled: usize = 0;
        errdefer for (out[0..filled]) |s| smallAlloc.free(s);
        for (strings, 0..) |s, i| {
            out[i] = smallAlloc.dupeZ(u8, s) catch return Errno.ENOMEM;
            filled += 1;
        }
        return out;
    }

    pub fn free_strings_z(strings: []const [:0]const u8) void {
        for (strings) |s| smallAlloc.free(s);
        smallAlloc.free(strings);
    }

    pub const ExecRequest = struct {
        data: []const u8,
        argv: []const [:0]const u8,
        envp: []const [:0]const u8,
    };

    /// Everything about an exec that can fail: read the image, validate it, and copy
    /// argv/envp into kernel memory. Touches no task, so on error nothing is committed
    /// and the caller's own resources are still safe to release.
    /// The returned request is owned by the matching commit_exec.
    pub fn prepare_exec(
        inode: *INode,
        argv: []const []const u8,
        envp: []const []const u8,
    ) Errno!*ExecRequest {
        const file = try inode.open();
        defer file.close() catch {};

        var magic: [2]u8 = undefined;
        if (try file.pread(0, magic[0..]) != magic.len) {
            return Errno.EINVAL;
        }
        if (std.mem.eql(u8, magic[0..], "#!")) {
            @panic("Must implement shebang");
        }

        const data = heapAlloc.alloc(u8, std.math.cast(usize, inode.size) orelse return Errno.E2BIG) catch
            return Errno.ENOMEM;
        errdefer heapAlloc.free(data);
        if (try file.pread(0, data) != data.len)
            return Errno.EIO;
        elf.validate(data) catch |e| return switch (e) {
            error.InvalidElf, error.UnsupportedElf => Errno.ENOEXEC,
            error.LoadFailed => unreachable, // validate do not map anything
        };

        var count: usize = 0;
        for (argv) |arg| count += arg.len + 1;
        for (envp) |env| count += env.len + 1;
        if (count > sysv.arg_max) return Errno.E2BIG;

        const argv_z = try dupe_strings_z(argv);
        errdefer free_strings_z(argv_z);
        const envp_z = try dupe_strings_z(envp);
        errdefer free_strings_z(envp_z);

        const req = smallAlloc.create(ExecRequest) catch return Errno.ENOMEM;
        req.* = .{ .data = data, .argv = argv_z, .envp = envp_z };
        return req;
    }

    /// The half that cannot fail, and does not come back: it resets the kernel stack
    /// the caller is running on.
    pub fn commit_exec(self: *Self, req: *ExecRequest) void {
        self.spawn(&exec_entry, @intFromPtr(req)) catch @panic("Failed to spawn exec task");
    }

    fn load_image(
        file_data: []const u8,
        argv_z: []const [:0]const u8,
        envp_z: []const [:0]const u8,
    ) !userspace.PreparedEntry {
        // load() copies every PT_LOAD into the new vm, and build_sysv_stack copies
        // the strings onto the user stack: none of these outlive this function.
        defer heapAlloc.free(file_data);
        defer free_strings_z(argv_z);
        defer free_strings_z(envp_z);

        const self = scheduler.get_current_task();

        const new_vm = try create_vm();
        errdefer destroy_vm(new_vm);

        const image = try elf.load(new_vm, file_data);

        userspace.map_userspace(new_vm);
        const entry = userspace.prepare_entry(new_vm, image, argv_z, envp_z);

        self.deinit_vm();
        self.vm = new_vm;
        return entry;
    }

    fn exec_entry(data: usize) u8 {
        const request: *ExecRequest = @ptrFromInt(data);
        const file_data = request.data;
        const argv_z = request.argv;
        const envp_z = request.envp;
        smallAlloc.destroy(request);

        // Everything fallible lives in a function that actually returns, so its
        // defer/errdefer run, only the ring-3 jump below is noreturn, and by then
        // there is nothing left to release.
        const entry = load_image(file_data, argv_z, envp_z) catch exit(1);
        userspace.iret_to(entry);
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
            // Marks the task; not returning to userspace is decided in wrapper.
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

    /// Queue a signal, and decide here what it does to a task that is not
    /// running: signals are only acted on when a task returns to userspace.
    pub fn send_signal(self: *Self, sig: signal.siginfo_t) void {
        const id = sig.si_signo.safeUnwrap() orelse return;

        // A stop and a continue cancel each other out, POSIX 2.4.3.
        switch (self.signalManager.get_defaultAction(id)) {
            .Continue => for ([_]signal.Id{ .SIGSTOP, .SIGTSTP, .SIGTTIN, .SIGTTOU }) |stop|
                self.signalManager.discard(stop),
            .Stop => self.signalManager.discard(.SIGCONT),
            else => {},
        }

        self.signalManager.queue_signal(sig);

        if (self.state == .Stopped) {
            // SIGKILL too: it can be neither blocked nor ignored.
            if (id == .SIGCONT or id == .SIGKILL) {
                self.state = .Ready;
                ready_queue.push(self);
            }
        } else if (self.state == .Blocked) {
            @import("wait_queue.zig").interrupt(self);
        }
    }

    pub noinline fn spawn(self: *Self, function: *const fn (usize) u8, data: usize) !void {
        scheduler.enter_critical();
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
        scheduler.exit_critical();
    }

    pub export fn start_task(self: *Self, function_ptr: *void, data: usize) callconv(.c) noreturn {
        const function: *const fn (usize) u8 = @ptrCast(function_ptr);
        self.state = .Running;
        scheduler.set_current_task(self);
        gdt.tss.esp0 = @as(usize, @intFromPtr(&self.stack)) + self.stack.len;
        gdt.flush();
        apply_tls(self);
        scheduler.exit_critical();
        exit(function(data));
    }

    pub fn chdir(self: *Self, new_dir: *TNode) void {
        if (new_dir.inode.mode.type != .Directory) {
            @panic("todo");
        }
        self.cwd.release();
        self.cwd = new_dir.get_ref();
    }
};

/// Load the task's TLS segment: refresh the GDT entry and reload %gs so its
/// cached descriptor picks up the new base. The selector is DPL 3 and
/// survives the iret back to userspace.
pub fn apply_tls(t: *TaskDescriptor) void {
    if (t.tls_base) |base| {
        gdt.set_tls(base);
        cpu.load_gs(.{ .index = gdt.tls_index, .table = .GDT, .privilege = .User });
    }
}

pub noinline fn switch_to_task_opts(prev: *TaskDescriptor, next: *TaskDescriptor) void {
    asm volatile (
        \\ pushal
        \\ mov %cr3, %eax
        \\ push %eax
    );
    asm volatile (
        \\push %[lock_depth]
        :
        : [lock_depth] "r" (scheduler.lock_depth),
    );

    prev.esp = cpu.get_esp();
    cpu.set_esp(next.esp);

    scheduler.lock_depth = asm volatile (
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
    scheduler.enter_critical();
    defer scheduler.exit_critical();

    if (prev.state == .Running) {
        ready_queue.push(prev);
    }
    next.state = .Running;

    gdt.tss.esp0 = @as(usize, @intFromPtr(&next.stack)) + next.stack.len;
    gdt.flush();
    apply_tls(next);

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
    scheduler.enter_critical();

    const task = scheduler.get_current_task();
    task.state = .Zombie;
    task.update_status(.{
        .transition = .Terminated,
        .signaled = false,
        .siginfo = .{
            .si_status = code,
        },
    });

    for (on_terminate_callback.items) |callback|
        callback(task);

    scheduler.schedule();
    unreachable;
}
