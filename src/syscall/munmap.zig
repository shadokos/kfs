const Errno = @import("../errno.zig").Errno;
const scheduler = @import("../task/scheduler.zig");
const paging = @import("../memory/paging.zig");

pub const Id = 13;

pub fn do(addr: *allowzero void, len: usize) !void {
    const task = scheduler.get_current_task();
    const vm = task.vm.?;

    if (len % paging.page_size != 0 or @as(usize, @intFromPtr(addr)) % paging.page_size != 0) {
        return Errno.EINVAL;
    }
    // todo: check int overflow

    vm.unmap(
        @as(usize, @intFromPtr(addr)) / paging.page_size,
        len / paging.page_size,
    ) catch @panic("todo"); // probably no error should happen
}
