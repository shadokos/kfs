const paging = @import("paging.zig");
const ft = @import("../ft/ft.zig");
const cpu = @import("../cpu.zig");
const logger = @import("../ft/ft.zig").log.scoped(.mapping);

pub const Directory: type = extern struct {
    userspace: [768]paging.TableEntry = [1]paging.TableEntry{.{ .not_mapped = .{} }} ** 768,
    _kernelspace: [255]paging.TableEntry = undefined,
    directory: paging.TableEntry = undefined,
};

/// return the physical address of a virtual ptr
pub fn get_physical_ptr(virtual: paging.VirtualPtr) error{ NotMapped, NotPresent }!paging.PhysicalPtr {
    const virtualStruct: paging.VirtualPtrStruct = @bitCast(@as(u32, @intFromPtr(virtual)));
    if (!is_page_mapped(paging.page_dir_ptr[virtualStruct.dir_index])) {
        return error.NotMapped;
    }
    const table: *volatile [paging.page_table_size]paging.TableEntry = get_table_ptr(virtualStruct.dir_index);
    if (!is_page_mapped(table[virtualStruct.table_index])) {
        return error.NotMapped;
    }
    if (!is_page_present(table[virtualStruct.table_index])) {
        return error.NotPresent;
    }
    const page: paging.PhysicalPtr = @as(
        paging.PhysicalPtr,
        table[virtualStruct.table_index].present.address_fragment,
    ) << 12;
    return page + virtualStruct.page_index;
}

pub fn is_page_mapped(table_entry: paging.TableEntry) bool {
    return @as(u32, @bitCast(table_entry)) != 0;
}

pub fn is_page_present(table_entry: paging.TableEntry) bool {
    return @as(u32, @bitCast(table_entry)) & 1 != 0;
}

/// return a virtual ptr to the table `table`
pub fn get_table_ptr(table: paging.dir_idx) *[paging.page_table_size]paging.TableEntry {
    return @ptrFromInt(@as(u32, @bitCast(paging.VirtualPtrStruct{
        .dir_index = paging.page_dir >> 22,
        .table_index = table,
        .page_index = 0,
    })));
}

/// return the page frame descriptor of the page pointed by `address`
pub fn get_page_frame_descriptor(address: paging.VirtualPagePtr) !*paging.page_frame_descriptor {
    const physical = try get_physical_ptr(@ptrCast(address));
    return @import("../memory.zig").pageFrameAllocator.get_page_frame_descriptor(physical);
}

pub fn set_entry(virtual: paging.VirtualPagePtr, entry: paging.TableEntry) void {
    const virtualStruct: paging.VirtualPtrStruct = @bitCast(@intFromPtr(virtual));
    const table = get_table_ptr(virtualStruct.dir_index);
    table[virtualStruct.table_index] = entry;
    cpu.reload_cr3();
}

pub fn get_entry(virtual: paging.VirtualPagePtr) paging.TableEntry {
    const virtualStruct: paging.VirtualPtrStruct = @bitCast(@intFromPtr(virtual));
    const table = get_table_ptr(virtualStruct.dir_index);
    return table[virtualStruct.table_index];
}

pub fn transfer(new: *align(4096) Directory) void {
    cpu.set_cr3(get_physical_ptr(@ptrCast(new)) catch unreachable);
}
