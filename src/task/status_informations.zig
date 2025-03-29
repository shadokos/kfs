const signal = @import("signal.zig");

pub const Status = struct {
    transition: Transition = undefined,
    signaled: bool = undefined,
    siginfo: signal.siginfo_t = undefined,
    pub const Transition = enum(u8) {
        Stopped = 0,
        Continued = 1,
        Terminated = 2,
    };

    pub const TransitionMask = packed struct(u3) {
        Stopped: bool = false,
        Continued: bool = false,
        Terminated: bool = false,

        pub const Self = @This();

        pub fn add(self: *Self, transition: Transition) void {
            @field(self.*, @tagName(transition)) = true;
        }

        pub fn remove(self: *Self, transition: Transition) void {
            @field(self.*, @tagName(transition)) = false;
        }

        pub fn check(self: Self, transition: Transition) bool {
            return switch (transition) {
                inline else => |t| @field(self, @tagName(t)),
            };
        }
    };
};
