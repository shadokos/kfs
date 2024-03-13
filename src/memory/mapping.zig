const paging = @import("paging.zig");
const ft = @import("../ft/ft.zig");
const cpu = @import("../cpu.zig");
const VirtualSpaceAllocator = @import("virtual_space_allocator.zig").VirtualSpaceAllocator;

/// return the physical address of a virtual ptr // todo: type to VirtualPtr
pub fn get_physical_ptr(virtual: paging.VirtualPtr) error{NotMapped}!paging.PhysicalPtr { // todo error
    const virtualStruct: paging.VirtualPtrStruct = @bitCast(@as(u32, @intFromPtr(virtual)));
    if (!paging.page_dir_ptr[virtualStruct.dir_index].present) {
        return error.NotMapped;
    }
    const table: *[paging.page_table_size]paging.page_table_entry = get_table_ptr(virtualStruct.dir_index);
    if (!table[virtualStruct.table_index].present) {
        return error.NotMapped;
    }
    const page: paging.PhysicalPtr = @as(paging.PhysicalPtr, table[virtualStruct.table_index].address_fragment) << 12;
    return page + virtualStruct.page_index;
}

pub fn is_page_mapped(table_entry: paging.page_table_entry) bool {
    return @as(u32, @bitCast(table_entry)) != 0;
}

/// return a virtual ptr to the table `table`
pub fn get_table_ptr(table: paging.dir_idx) *[paging.page_table_size]paging.page_table_entry {
    return @ptrFromInt(@as(u32, @bitCast(paging.VirtualPtrStruct{
        .dir_index = paging.page_dir >> 22,
        .table_index = table,
        .page_index = 0,
    })));
}

pub fn MapperT(comptime PageFrameAllocatorType: type) type {
    return struct {
        /// underlying page frame allocator instance, used to allocate tables
        pageFrameAllocator: *PageFrameAllocatorType = undefined,

        /// page directory used by this mapping
        page_directory: [paging.page_directory_size]paging.page_directory_entry align(paging.page_size) = undefined,

        pub const Error = error{ AlreadyMapped, NotMapped, MisalignedPtr };

        const Self = @This();

        pub fn init(self: *Self, _pageFrameAllocator: *PageFrameAllocatorType) PageFrameAllocatorType.Error!void {
            self.pageFrameAllocator = _pageFrameAllocator;

            try self.transfer();
        }

        /// init the table `table`
        fn init_table(self: *Self, table: paging.dir_idx) PageFrameAllocatorType.Error!void {
            const table_physical_ptr: paging.PhysicalPtr = try self.pageFrameAllocator.alloc_pages(1);

            self.page_directory[table] = .{
                .address_fragment = @truncate(table_physical_ptr >> paging.page_bits),
                .present = true,
                .owner = if (table >= (paging.low_half >> 22)) .Supervisor else .User,
                .writable = true,
            };

            const table_virtual_ptr: *[paging.page_table_size]paging.page_table_entry = @ptrFromInt(@as(u32, @bitCast(paging.VirtualPtrStruct{
                .dir_index = paging.page_dir >> 22,
                .table_index = table,
                .page_index = 0,
            })));

            @memset(table_virtual_ptr[0..], paging.page_table_entry{});
        }

        /// map one page
        fn map_one(self: *Self, virtual: paging.VirtualPagePtr, physical: paging.PhysicalPtr) (PageFrameAllocatorType.Error || Error)!void {
            const virtualStruct: paging.VirtualPtrStruct = @bitCast(@intFromPtr(virtual));

            if (!self.page_directory[virtualStruct.dir_index].present)
                try self.init_table(virtualStruct.dir_index);

            const table = get_table_ptr(virtualStruct.dir_index);

            const entry: paging.page_table_entry = .{
                .address_fragment = @truncate(physical >> paging.page_bits),
                .present = true,
                .owner = .User,
                .writable = true,
            };

            if (is_page_mapped(table[virtualStruct.table_index])) {
                if (@as(u32, @bitCast(table[virtualStruct.table_index])) == @as(u32, @bitCast(entry)))
                    return;
                return Error.AlreadyMapped;
            }
            table[virtualStruct.table_index] = entry;
            cpu.reload_cr3();
        }

        /// unmap npages pages
        pub fn unmap(self: *Self, virtual: paging.VirtualPagePtr, npages: usize) Error!void {
            for (0..npages) |i| {
                const virtualStruct: paging.VirtualPtrStruct = @bitCast(@intFromPtr(virtual) + i * paging.page_size);
                if (!self.page_directory[virtualStruct.dir_index].present) {
                    return Error.NotMapped;
                }
                const table = get_table_ptr(virtualStruct.dir_index);
                table[virtualStruct.table_index] = .{};
            }
            cpu.reload_cr3();
        }

        /// map `npages` pages (pointers must be aligned)
        pub fn map(self: *Self, virtual: paging.VirtualPagePtr, physical: paging.PhysicalPtr, npages: usize) (PageFrameAllocatorType.Error || Error)!void {
            if (!ft.mem.isAligned(physical, paging.page_size))
                return Error.MisalignedPtr;

            for (0..npages) |p| {
                try self.map_one(@ptrFromInt(@intFromPtr(virtual) + p * paging.page_size), physical + p * paging.page_size);
            }
        }

        /// set R/W rights for the virtual area pointed by virtual of size npages
        pub fn set_rights(self: *Self, virtual: paging.VirtualPagePtr, npages: usize, writable: bool) Error!void {
            for (0..npages) |i| {
                const virtualStruct: paging.VirtualPtrStruct = @bitCast(@intFromPtr(virtual) + i * paging.page_size);
                if (!self.page_directory[virtualStruct.dir_index].present) {
                    return Error.NotMapped;
                }
                const table = get_table_ptr(virtualStruct.dir_index);
                table[virtualStruct.table_index].writable = writable;
            }
        }

        /// load the page directory in cr3
        fn activate(self: *Self) void {
            cpu.set_cr3(get_physical_ptr(@ptrCast(&self.page_directory)) catch unreachable);
        }

        /// copy the active page directory and page tables to this page_directory
        fn transfer(self: *Self) (PageFrameAllocatorType.Error)!void {
            @memcpy(self.page_directory[0..], paging.page_dir_ptr);
            self.page_directory[paging.page_dir >> 22] = .{ .present = true, .writable = true, .owner = .Supervisor, .address_fragment = @truncate((get_physical_ptr(@ptrCast(&self.page_directory)) catch unreachable) >> 12) };
            self.activate();
            const virtual_tmp: @TypeOf(paging.page_table_table_ptr) = @ptrFromInt(paging.temporary_page);
            for (paging.page_table_table_ptr[0..(paging.low_half >> 22)], 0..) |*e, i| {
                if (e.present and i != (paging.page_dir >> 20)) {
                    const physical = try self.pageFrameAllocator.alloc_pages(1);
                    self.map_one(@ptrCast(virtual_tmp), physical) catch unreachable;
                    @memcpy(virtual_tmp[0..], get_table_ptr(@truncate(i)));
                    self.unmap(@ptrCast(virtual_tmp), 1) catch unreachable;
                    e.address_fragment = @truncate(physical >> 12);
                }
            }
        }
    };
}
