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
};
