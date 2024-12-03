const pit = @import("../drivers/pit/pit.zig");

pub fn sys_nanosleep(ns: u32) void {
    pit.nano_sleep(ns);
}
