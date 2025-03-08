const Errno = @import("../errno.zig").Errno;
const scheduler = @import("../task/scheduler.zig");
const paging = @import("../memory/paging.zig");
const VirtualSpace = @import("../memory/virtual_space.zig").VirtualSpace;
const regions = @import("../memory/regions.zig");
const RegionSet = @import("../memory/region_set.zig").RegionSet;
const ft = @import("ft");
const tty = @import("../tty/tty.zig");

pub const Id = 12;

pub const Prot = packed struct(u32) {
    PROT_READ: bool = false,
    PROT_WRITE: bool = false,
    PROT_EXEC: bool = false,
    _unused: u29 = 0,
};

const Privacy = enum(u2) {
    Private = 0b01,
    Shared = 0b10,
};

pub const Flags = packed struct(u32) {
    anonymous: bool = false,
    privacy: Privacy = .Private,
    fixed: bool = false, // todo: implement this flag
    noreplace: bool = false,
    _unused: u27 = 0,
};

fn create_anonymous_mapping(addr: ?*void, len: usize, prot: Prot, flags: Flags) !*allowzero void {
    const task = scheduler.get_current_task();
    const vm = task.vm.?;

    const npage = ft.math.divCeil(
        usize,
        len,
        paging.page_size,
    ) catch unreachable;

    const region = RegionSet.create_region() catch return Errno.ENOMEM;
    errdefer RegionSet.destroy_region(region) catch unreachable;

    region.flags.may_read = true;
    region.flags.may_write = true;

    region.flags.read = prot.PROT_READ or prot.PROT_EXEC or prot.PROT_WRITE;
    region.flags.write = prot.PROT_WRITE;

    regions.VirtuallyContiguousRegion.init(region, .{
        .private = flags.privacy == .Private,
    });

    if (addr) |addr_value| {
        if (@as(usize, @intFromPtr(addr_value)) % paging.page_size != 0) // todo: misaligned addr
            @panic("todo");
        const addr_page = @as(usize, @intFromPtr(addr_value)) / paging.page_size;
        vm.add_region_at(region, addr_page, npage, !flags.noreplace) catch {
            if (flags.fixed)
                return Errno.EINVAL;
            vm.add_region(region, npage) catch @panic("todo");
        };
    } else {
        vm.add_region(region, npage) catch @panic("todo");
    }

    return @ptrFromInt(region.begin * paging.page_size);
}

//void *addr, size_t len, int prot, int flags, int fildes, off_t off
pub fn do(addr: ?*void, len: usize, prot: Prot, flags: Flags, fildes: i32, off: isize) !*allowzero void {
    _ = fildes;
    _ = off;
    // todo : sanitize input

    return if (flags.anonymous)
        create_anonymous_mapping(addr, len, prot, flags)
    else
        @panic("file mapping not implemented yet");
}
