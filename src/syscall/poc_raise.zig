pub const Id = 3;

const SigHandler = @import("../userspace.poc.zig").SigHandler;
const queue_signal = @import("../userspace.poc.zig").queue_signal;

pub fn do(handler: SigHandler) !void {
    queue_signal(handler);
}
