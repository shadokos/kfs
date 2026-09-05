// A session and the terminal it may own. POSIX 11.1.3: a controlling terminal
// belongs to a session and not to a task, so every task of a session sees the
// same one and sees it change at the same time.

const std = @import("std");

const TaskDescriptor = @import("task.zig").TaskDescriptor;
const TtyStruct = @import("../tty/TtyStruct.zig");

const allocator = @import("../memory.zig").smallAlloc.allocator();

const Self = @This();

/// The pid of the task that created the session, and its name.
sid: TaskDescriptor.Pid,

/// The terminal this session controls, if it has claimed one.
ctty: ?*TtyStruct = null,

/// How many tasks belong to the session.
refs: usize = 0,

pub fn create(sid: TaskDescriptor.Pid) !*Self {
    const self = allocator.create(Self) catch return error.ENOMEM;
    self.* = .{ .sid = sid, .refs = 1 };
    return self;
}

pub fn get_ref(self: *Self) *Self {
    self.refs += 1;
    return self;
}

/// The last task of a session takes its terminal with it.
pub fn release(self: *Self) void {
    std.debug.assert(self.refs > 0);
    self.refs -= 1;
    if (self.refs != 0) return;

    if (self.ctty) |terminal| self.disown(terminal);
    allocator.destroy(self);
}

/// Claim a terminal, POSIX 11.1.3: the foreground process group becomes that
/// of the session leader. Fails when the terminal already answers to someone.
pub fn claim(self: *Self, terminal: *TtyStruct, leader_pgid: TaskDescriptor.Pid) !void {
    if (self.ctty != null) return error.EPERM;
    if (terminal.session != null) return error.EPERM;

    self.ctty = terminal;
    terminal.session = self;
    _ = terminal.set_foreground_pgid(leader_pgid);
}

/// Give the terminal back with no foreground group left to signal.
pub fn disown(self: *Self, terminal: *TtyStruct) void {
    if (self.ctty != terminal) return;
    self.ctty = null;
    terminal.session = null;
    _ = terminal.set_foreground_pgid(null);
}
