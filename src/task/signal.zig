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
const Mutex = @import("semaphore.zig").Mutex;

pub const DefaultAction = enum {
    Ignore,
    Terminate,
    Stop,
    Continue,
};

pub const Handler = *allowzero const fn (u32) callconv(.C) void;
pub const SigactionHandler = *allowzero const fn (u32, *siginfo_t, *void) callconv(.C) void;
pub const SIG_DFL: Handler = @ptrFromInt(0);
pub const SIG_IGN: Handler = @ptrFromInt(1);

// ids according to the system V i386 ABI
pub const Id = enum(u32) {
    SIGHUP = 1,
    SIGINT = 2,
    SIGQUIT = 3,
    SIGILL = 4,
    SIGTRAP = 5,
    SIGABRT = 6,
    SIGEMT = 7,
    SIGFPE = 8,
    SIGKILL = 9,
    SIGBUS = 10,
    SIGSEGV = 11,
    SIGSYS = 12,
    SIGPIPE = 13,
    SIGALRM = 14,
    SIGTERM = 15,
    SIGUSR1 = 16,
    SIGUSR2 = 17,
    SIGCHLD = 18,
    SIGPWR = 19,
    SIGWINCH = 20,
    SIGURG = 21,
    SIGPOLL = 22,
    SIGSTOP = 23,
    SIGTSTP = 24,
    SIGCONT = 25,
    SIGTTIN = 26,
    SIGTTOU = 27,
    SIGVTALRM = 28,
    SIGPROF = 29,
    SIGXCPU = 30,
    SIGXFSZ = 31,
};

pub const Code = enum(u32) {
    SI_USER,
    SEGV_ACCERR,
    SEGV_MAPERR,
};

pub const siginfo_t = extern struct {
    si_signo: Signo = Signo.invalid,
    si_code: Code = undefined,
    si_errno: u32 = undefined,
    si_pid: TaskDescriptor.Pid = undefined, // todo pid type
    // si_uid
    si_addr: paging.VirtualPtr = undefined,
    si_status: u32 = undefined,
    // si_value : sigval
    pub const Signo = packed union {
        valid: Id,
        null: Monostate(u32, 0),
        pub const invalid = @This(){ .null = .{} };
        pub fn make(id: Id) @This() {
            return .{ .valid = id };
        }
        pub fn unwrap(self: @This()) Id {
            return if (@as(u32, @bitCast(self)) == 0) @panic("invalid signo") else self.valid;
        }
        pub fn safeUnwrap(self: @This()) ?Id {
            return if (@as(u32, @bitCast(self)) == 0) null else self.valid;
        }
    };
};

pub const SigSet = u32;

pub const Sigaction = extern struct {
    sa_handler: Handler = SIG_DFL,
    sa_sigaction: SigactionHandler = undefined,
    sa_mask: SigSet = 0,
    sa_flags: packed struct(u32) {
        SA_NOCLDSTOP: bool = false, // todo: implement this option
        // SA_ONSTACK, : bool = false,
        SA_RESETHAND: bool = false, // todo: implement this option
        SA_RESTART: bool = false, // todo: implement this option
        SA_SIGINFO: bool = false,
        // SA_NOCLDWAIT : bool = false,
        SA_NODEFER: bool = false, // todo
        // SS_ONSTACK : bool = false,
        // SS_DISABLE : bool = false,
        // MINSIGSTKSZ : bool = false,
        // SIGSTKSZ : bool = false,
        _unused: u27 = 0,
    } = .{},
};

pub const SignalQueue = struct {
    default_handler: DefaultAction,
    action: Sigaction,
    queue: QueueType = .{},
    ignorable: bool = true,

    const QueueType = ft.DoublyLinkedList(siginfo_t);
    pub var cache: *Cache = undefined;
    const Self = @This();

    pub fn init(default_handler: DefaultAction, ignorable: bool) Self {
        return Self{
            .default_handler = default_handler,
            .action = .{ .sa_handler = SIG_DFL },
            .ignorable = ignorable,
        };
    }

    pub fn init_cache() !void {
        cache = try globalCache.create(
            "signal node",
            @import("../memory.zig").virtually_contiguous_page_allocator.page_allocator(),
            @sizeOf(QueueType.Node),
            @alignOf(QueueType.Node),
            3,
        );
    }

    fn is_ignored(self: Self) bool {
        return !self.action.sa_flags.SA_SIGINFO and
            (self.action.sa_handler == SIG_IGN or
                (self.action.sa_handler == SIG_DFL and self.default_handler == .Ignore));
    }

    pub fn queue_signal(self: *Self, signal: siginfo_t) void {
        if (self.is_ignored()) {
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

    pub fn set_action(self: *Self, action: Sigaction) !void {
        if (!self.ignorable)
            return Errno.EINVAL;
        self.action = action;
        if (self.is_ignored()) {
            while (self.queue.len != 0) {
                _ = self.queue.pop();
            }
        }
    }
};

pub const SignalManager = struct {
    queues: [32]SignalQueue = undefined,
    pending: SigSet = 0,
    mutex: Mutex = .{},
    const Self = @This();

    const non_maskable: SigSet = (@as(SigSet, 1) << @intFromEnum(Id.SIGKILL)) |
        (@as(SigSet, 1) << @intFromEnum(Id.SIGSTOP));

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

    pub fn change_action(self: *Self, id: Id, action: Sigaction) !void {
        self.mutex.acquire();
        defer self.mutex.release();

        return self.queues[@intFromEnum(id)].set_action(action);
    }

    pub fn get_action(self: Self, id: Id) Sigaction {
        return self.queues[@intFromEnum(id)].action;
    }

    pub fn get_defaultAction(self: Self, id: Id) DefaultAction {
        return self.queues[@intFromEnum(id)].default_handler;
    }

    pub fn queue_signal(self: *Self, signal: siginfo_t) void {
        self.mutex.acquire();
        defer self.mutex.release();

        const index: u32 = @intFromEnum(signal.si_signo.unwrap());
        if (index > self.queues.len) {
            @panic("todo");
        }
        self.queues[index].queue_signal(signal);
        if (self.queues[index].queue.len != 0) { // todo: there may be a better way to do this
            self.pending |= @as(SigSet, 1) << @as(u5, @intCast(index));
        }
    }

    pub fn get_pending_signal(self: *Self, mask: SigSet) ?siginfo_t {
        self.mutex.acquire();
        defer self.mutex.release();

        const real_mask: SigSet = mask & ~non_maskable;
        if ((self.pending & ~real_mask) != 0) {
            const signo = @ctz(self.pending & ~real_mask);
            const q = &self.queues[signo];
            if (q.pop()) |s| {
                if (q.queue.len == 0) {
                    self.pending ^= @as(SigSet, 1) << @intCast(signo);
                }
                return s;
            } else unreachable;
        }
        return null;
    }

    pub fn has_pending(self: Self) bool {
        return self.pending != 0;
    }
};
