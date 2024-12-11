const ps2 = @import("../drivers/ps2/ps2.zig");

pub const Id = 5;

pub fn do() !void {
    ps2.cpu_reset();
}
