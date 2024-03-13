const ft = @import("../ft/ft.zig");

/// page index type
pub const idx_t = usize;

/// order type (for buddy allocation)
pub const order_t = ft.meta.Int(.unsigned, ft.math.log2(@typeInfo(idx_t).Int.bits));

/// flags of a page frame
pub const page_flags = packed struct {
    available: bool = false,
    slab: bool = false,
};

/// page frame descriptor
pub const page_frame_descriptor = struct { flags: page_flags, next: ?*page_frame_descriptor = null, prev: ?*page_frame_descriptor = null };

pub const page_table_size = 1024;

pub const page_directory_size = 1024;

pub const page_size = 4096;

pub const page_bits = ft.math.log2(page_size);

/// page
pub const page = [page_size]u8;

pub const PhysicalPtr = u32;
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

pub const virtual_size = 0xffffffff + 1;
pub const page_dir = virtual_size - page_size;
pub const page_table_table = page_dir;
pub const page_tables = virtual_size - page_size * page_directory_size;
pub const temporary_page = page_tables - page_size;
// pub const kernel_tables = 0xffefd000;

pub const low_half = 0xC0000000;
pub const kernel_virtual_space_top = temporary_page;
pub const kernel_virtual_space_size = kernel_virtual_space_top - low_half;

pub const page_dir_ptr: *align(4096) [page_directory_size]page_directory_entry = @ptrFromInt(page_dir);
pub const page_table_table_ptr: *align(4096) [page_table_size]page_table_entry = @ptrFromInt(page_table_table);
// pub const kernel_tables_ptr : *[256][page_table_size]page_table_entry = @ptrFromInt(kernel_tables);

pub fn is_user_space(p: VirtualPagePtr) bool {
    return @intFromPtr(p) < low_half;
}
