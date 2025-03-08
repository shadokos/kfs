const Errno = @import("../errno.zig").Errno;
const scheduler = @import("../task/scheduler.zig");
const paging = @import("../memory/paging.zig");
const Prot = @import("mmap.zig").Prot;
const ft = @import("ft");
const regions = @import("../memory/regions.zig");
const Region = regions.Region;

pub const Id = 14;

pub fn do(addr: *allowzero void, len: usize, prot: Prot) !void {
    const task = scheduler.get_current_task();
    const vm = task.vm.?;

    if (@as(usize, @intFromPtr(addr)) % paging.page_size != 0) {
        return Errno.EINVAL;
    }
    const first_page = @as(usize, @intFromPtr(addr)) / paging.page_size;
    const npage = ft.math.divCeil(usize, len, paging.page_size) catch unreachable;
    // todo: check int overflow

    var it = vm.regions.get_range_iterator(first_page, npage);

    var previous: usize = first_page;
    while (it.next()) |region| {
        if (previous != region.begin or
            (prot.PROT_WRITE and !region.flags.may_write) or
            (prot.PROT_READ and !region.flags.may_read))
            return Errno.ENOMEM; // range cover pages which are not mapped or invalid
        previous = region.begin + region.len;
    } else {
        if (previous != first_page + npage)
            return Errno.ENOMEM; // range cover pages which are not mapped or invalid
    }

    it = vm.regions.get_range_iterator(first_page, npage);
    while (it.next()) |region| {
        const isolated = vm.isolate_region(region, first_page, npage) catch @panic("todo");
        isolated.flags.write = prot.PROT_WRITE;
        isolated.flags.read = prot.PROT_READ;
        isolated.flush();
    }
}
