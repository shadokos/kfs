const std = @import("std");
const Monostate = @import("../misc/monostate.zig").Monostate;

/// page index type
pub const idx_t = usize;

/// order type (for buddy allocation)
pub const order_t = std.meta.Int(.unsigned, std.math.log2(@typeInfo(idx_t).int.bits));

/// flags of a page frame
pub const page_flags = packed struct {
    available: bool = false,
    slab: bool = false,
};

/// page frame descriptor
pub const page_frame_descriptor = struct {
    flags: page_flags,
    next: ?*page_frame_descriptor = null,
    prev: ?*page_frame_descriptor = null,
};

pub const page_table_size = 1024;

pub const page_directory_size = 1024;

pub const page_size = 4096;

pub const page_bits = std.math.log2(page_size);

/// page
pub const page = [page_size]u8;

pub const PhysicalPtr = u32;
pub const PhysicalUsize = u32;
pub const PhysicalPtrDiff = std.meta.Int(.signed, @typeInfo(PhysicalPtr).int.bits + 1);

pub const VirtualPtr = *allowzero void;
pub const VirtualPagePtr = *allowzero align(4096) page;

pub const dir_idx = u10;
pub const table_idx = u10;

pub const VirtualPtrStruct = packed struct(u32) {
    page_index: u12,
    table_index: table_idx,
    dir_index: dir_idx,
};

pub const physical_memory_max: PhysicalPtr = ~@as(PhysicalPtr, 0);

pub const page_directory_entry = packed struct(u32) {
    present: bool = false,
    writable: bool = false,
    owner: enum(u1) {
        Supervisor = 0,
        User = 1,
    } = .Supervisor,
    write_through: bool = false,
    cache_disable: bool = false,
    accessed: bool = false,
    unused2: u1 = 0,
    page_size: enum(u1) {
        Small = 0,
        Big = 1,
    } = .Small,
    unused: u4 = 0,
    address_fragment: u20 = 0,
};

pub const page_table_entry = packed struct(u32) {
    present: bool = false,
    writable: bool = false,
    owner: enum(u1) {
        Supervisor = 0,
        User = 1,
    } = .Supervisor,
    write_through: bool = false,
    cache_disable: bool = false,
    accessed: bool = false,
    dirty: bool = false,
    page_size: enum(u1) {
        Small = 0,
        Big = 1,
    } = .Small,
    global: bool = false,
    unused: u3 = 0,
    address_fragment: u20 = 0,
};

pub const present_table_entry = packed struct(u32) {
    present: Monostate(u1, 1) = .{},
    writable: bool = false,
    owner: enum(u1) {
        Supervisor = 0,
        User = 1,
    } = .Supervisor,
    _reserved_1: Monostate(u2, 0) = .{},
    accessed: bool = false,
    dirty: bool = false,
    _reserved_2: Monostate(u2, 0) = .{},
    unused: u3 = 0,
    address_fragment: u20 = 0,
};

pub const TableEntry = packed union {
    present: present_table_entry,
    not_present: *align(2) void,
    not_mapped: Monostate(u32, 0),
    pub fn is_present(self: TableEntry) bool {
        return @as(u32, @bitCast(self)) & 1 == 1;
    }
    pub fn is_mapped(self: TableEntry) bool {
        return @as(u32, @bitCast(self)) != 0;
    }
};

pub const virtual_size = 0xffffffff + 1;
pub const page_dir = virtual_size - page_size;
pub const page_table_table = page_dir;
pub const page_tables = virtual_size - page_size * page_directory_size;
pub const kernel_page_tables = virtual_size - 256 * page_size;

pub const high_half = 0xC0000000;
pub const kernel_virtual_space_top = page_tables;
pub const kernel_virtual_space_size = kernel_virtual_space_top - high_half;

pub const direct_zone_size = 128 * (1 << 20);

pub const page_dir_ptr: *align(4096) volatile [page_directory_size]TableEntry = @ptrFromInt(page_dir);
pub const page_table_table_ptr: *align(4096) volatile [page_table_size]TableEntry = @ptrFromInt(page_table_table);
// pub const kernel_tables_ptr : *[256][page_table_size]page_table_entry = @ptrFromInt(kernel_tables);

pub fn is_user_space(p: VirtualPagePtr) bool {
    return @intFromPtr(p) < high_half;
}
