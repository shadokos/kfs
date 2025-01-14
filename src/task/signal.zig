const ft = @import("ft");
const task = @import("task.zig");
const TaskDescriptor = task.TaskDescriptor;
const scheduler = @import("scheduler.zig");
const task_set = @import("task_set.zig");
const paging = @import("../memory/paging.zig");
const Monostate = @import("../misc/monostate.zig").Monostate;
const Cache = @import("../memory/object_allocators/slab/cache.zig").Cache;
const globalCache = &@import("../memory.zig").globalCache;
const Errno = @import("../errno.zig").Errno;
const logger = @import("ft").log.scoped(.signal);

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
//
// pub const Handler = struct {
//     type: Type,
//     func: ?*(fn (u32) void) = null,
//     const Type = enum {
//         Function,
//         Ignore,
//         Terminate,
//         Stop,
//         Continue,
//     };
// };
pub const DefaultAction = enum {
    Ignore,
    Terminate,
    Stop,
    Continue,
};

pub const Handler = *allowzero (fn (u32) void);
pub const SIG_DFL: Handler = @ptrFromInt(0);
pub const SIG_IGN: Handler = @ptrFromInt(1);

pub const Id = enum {
    SIGABRT,
    SIGALRM,
    SIGBUS,
    SIGCHLD,
    SIGCONT,
    SIGFPE,
    SIGHUP,
    SIGILL,
    SIGINT,
    SIGKILL,
    SIGPIPE,
    SIGQUIT,
    SIGSEGV,
    SIGSTOP,
    SIGTERM,
    SIGTSTP,
    SIGTTIN,
    SIGTTOU,
    SIGUSR1,
    SIGUSR2,
    SIGPOLL,
    SIGPROF,
    SIGSYS,
    SIGTRAP,
    SIGURG,
    SIGVTALRM,
    SIGXCPU,
    SIGXFSZ,
};

// pub const Sigaction = struct {
//     sa_handler: Handler,
// };

pub const SignalQueue = struct {
    default_handler: DefaultAction,
    handler: Handler,
    queue: QueueType = .{},
    ignorable: bool = true,

    const QueueType = ft.DoublyLinkedList(siginfo_t);
    pub var cache: *Cache = undefined;
    const Self = @This();

    pub fn init(default_handler: DefaultAction, ignorable: bool) Self {
        return Self{ .default_handler = default_handler, .handler = SIG_DFL, .ignorable = ignorable };
    }

    pub fn init_cache() !void {
        cache = try globalCache.create(
            "signal node",
            @import("../memory.zig").virtually_contiguous_page_allocator.page_allocator(),
            @sizeOf(QueueType.Node),
            3,
        );
    }

    pub fn queue_signal(self: *Self, signal: siginfo_t) void {
        if (self.handler == SIG_IGN or (self.handler == SIG_DFL and self.default_handler == .Ignore)) { // todo
            return;
        }
        const node = cache.allocator().create(QueueType.Node) catch @panic("out of space");
        self.queue.append(node);
        node.data = signal;
    }

    pub fn pop(self: *Self) ?siginfo_t {
        if (self.queue.pop()) |node| {
            const ret = node.data;
            cache.allocator().destroy(node);
            return ret;
        } else return null;
    }

    pub fn set_handler(self: *Self, handler: Handler) !void {
        // todo
        self.handler = handler;
        if (handler.type == SIG_IGN) {
            while (self.queue.len != 0) {
                _ = self.queue.pop();
            }
        }
    }
};

pub const SignalManager = struct {
    queues: [32]SignalQueue = undefined,
    pending: u32 = 0,
    const Self = @This();

    fn init_queue(self: *Self, id: Id, default_action: DefaultAction, ignorable: bool) void {
        self.queues[@intFromEnum(id)] = SignalQueue.init(default_action, ignorable);
    }
    pub fn init() Self {
        var self = Self{};
        self.init_queue(.SIGABRT, .Terminate, true);
        self.init_queue(.SIGALRM, .Terminate, true);
        self.init_queue(.SIGBUS, .Terminate, true);
        self.init_queue(.SIGCHLD, .Ignore, true);
        self.init_queue(.SIGCONT, .Continue, true);
        self.init_queue(.SIGFPE, .Terminate, true);
        self.init_queue(.SIGHUP, .Terminate, true);
        self.init_queue(.SIGILL, .Terminate, true);
        self.init_queue(.SIGINT, .Terminate, true);
        self.init_queue(.SIGKILL, .Terminate, false);
        self.init_queue(.SIGPIPE, .Terminate, true);
        self.init_queue(.SIGQUIT, .Terminate, true);
        self.init_queue(.SIGSEGV, .Terminate, true);
        self.init_queue(.SIGSTOP, .Stop, false);
        self.init_queue(.SIGTERM, .Terminate, true);
        self.init_queue(.SIGTSTP, .Stop, true);
        self.init_queue(.SIGTTIN, .Stop, true);
        self.init_queue(.SIGTTOU, .Stop, true);
        self.init_queue(.SIGUSR1, .Terminate, true);
        self.init_queue(.SIGUSR2, .Terminate, true);
        self.init_queue(.SIGPOLL, .Terminate, true);
        self.init_queue(.SIGPROF, .Terminate, true);
        self.init_queue(.SIGSYS, .Terminate, true);
        self.init_queue(.SIGTRAP, .Terminate, true);
        self.init_queue(.SIGURG, .Ignore, true);
        self.init_queue(.SIGVTALRM, .Terminate, true);
        self.init_queue(.SIGXCPU, .Terminate, true);
        self.init_queue(.SIGXFSZ, .Terminate, true);
        return self;
    }

    pub fn change_action(self: *Self, id: Id, action: Handler) !void {
        return self.queues[@intFromEnum(id)].set_handler(action);
    }

    pub fn get_action(self: *Self, id: Id) Handler {
        return self.queues[@intFromEnum(id)].handler;
    }

    pub fn get_defaultAction(self: *Self, id: Id) DefaultAction {
        return self.queues[@intFromEnum(id)].default_handler;
    }

    pub fn queue_signal(self: *Self, signal: siginfo_t) void {
        if (signal.si_signo > self.queues.len) {
            @panic("todo");
        }
        self.queues[signal.si_signo].queue_signal(signal);
        if (self.queues[signal.si_signo].queue.len != 0) { // todo
            self.pending |= @as(u32, 1) << @intCast(signal.si_signo);
        }
    }

    pub fn get_pending_signal(self: *Self) ?siginfo_t {
        if (self.pending != 0) {
            const signo = @ctz(self.pending);
            const q = &self.queues[signo];
            if (q.pop()) |s| {
                if (q.queue.len == 0) { // todo
                    self.pending &= ~(@as(u32, 1) << @intCast(signo));
                }
                return s;
            } else unreachable;
        }
        return null;
    }

    pub fn get_pending_signal_for_handler(self: *Self, handler: Handler) ?siginfo_t {
        var signo = @ctz(self.pending);
        while (signo < 32) {
            const q = &self.queues[signo];
            if (q.handler == handler) {
                if (q.pop()) |s| {
                    if (q.queue.len == 0) { // todo
                        self.pending &= ~(@as(u32, 1) << @intCast(signo));
                    }
                    return s;
                } else unreachable;
            }
            signo = @ctz((self.pending >> @intCast(signo)) >> 1) + signo;
        }
        return null;
    }

    pub fn has_pending(self: Self) bool {
        return self.pending != 0;
    }
};

pub fn kill(pid: TaskDescriptor.Pid, signal: Id) !void {
    const descriptor = task_set.get_task_descriptor(pid) orelse return Errno.ESRCH;
    // todo permisssion
    descriptor.signalManager.queue_signal(.{
        .si_signo = @intFromEnum(signal),
        // todo set more fields of siginfo
    });
}
