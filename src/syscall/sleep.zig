const pit = @import("../drivers/pit/pit.zig");

pub const Id = 1;

pub fn do(ns: u32) !void {
    pit.sleep(ns);
}
