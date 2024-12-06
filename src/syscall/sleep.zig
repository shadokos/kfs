const pit = @import("../drivers/pit/pit.zig");

pub fn sys_sleep(ns: u32) !u8 {
    pit.sleep(ns);
    return 0;
}
