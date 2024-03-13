const LinearAllocator = @import("linear_allocator.zig").LinearAllocator;
const StaticAllocator = @import("static_allocator.zig").StaticAllocator;
const BuddyAllocator = @import("buddy_allocator.zig").BuddyAllocator;
const paging = @import("paging.zig");

const max_order = 10;

pub var linearAllocator: StaticAllocator(BuddyAllocator(void, max_order).size_for(paging.virtual_size / paging.page_size)) = .{};

pub const PageFrameAllocator = struct {
    total_space: u64 = undefined,
    addressable_space_allocator: UnderlyingAllocator = .{},
    non_addressable_space_allocator: UnderlyingAllocator = .{},

    pub const UnderlyingAllocator = BuddyAllocator(@TypeOf(linearAllocator), max_order);

    pub const Error = UnderlyingAllocator.Error;

    const Self = @This();

    pub fn init(_total_space: u64) Self {
        var self = Self{ .total_space = _total_space };
        self.total_space = @min(self.total_space, paging.physical_memory_max);

        if (self.total_space > UnderlyingAllocator.max_possible_space(u64, &linearAllocator))
            @panic("Not enough space in page frame allocator!");

        self.addressable_space_allocator = UnderlyingAllocator.init(@truncate(@min(self.total_space, paging.physical_memory_max) / @sizeOf(paging.page)), &linearAllocator);

        if (self.total_space > paging.physical_memory_max) {
            const high_memory_space = self.total_space - paging.physical_memory_max;
            self.non_addressable_space_allocator = UnderlyingAllocator.init(@truncate(high_memory_space / @sizeOf(paging.page)), &linearAllocator);
        }
        return self;
    }

    pub fn alloc_pages(self: *Self, n: usize) Error!paging.PhysicalPtr {
        return if (self.non_addressable_space_allocator.alloc_pages(n)) |v|
            v * @sizeOf(paging.page) + paging.physical_memory_max
        else |_| if (self.addressable_space_allocator.alloc_pages(n)) |v|
            v * @sizeOf(paging.page)
        else |err|
            err;
    }

    pub fn alloc_pages_hint(self: *Self, hint: paging.PhysicalPtr, n: usize) Error!paging.PhysicalPtr {
        return if (self.non_addressable_space_allocator.alloc_pages_hint(hint / @sizeOf(paging.page), n)) |v|
            v * @sizeOf(paging.page) + paging.physical_memory_max
        else |_| if (self.addressable_space_allocator.alloc_pages_hint(hint / @sizeOf(paging.page), n)) |v|
            v * @sizeOf(paging.page)
        else |err|
            err;
    }

    pub fn free_pages(self: *Self, ptr: paging.PhysicalPtr, n: usize) !void {
        return if (ptr < paging.physical_memory_max)
            self.addressable_space_allocator.free_pages(@truncate(ptr / @sizeOf(paging.page)), n)
        else
            self.non_addressable_space_allocator.free_pages(@truncate(ptr / @sizeOf(paging.page)), n);
    }

    pub fn get_page_frame_descriptor(self: *Self, ptr: paging.PhysicalPtr) *paging.page_frame_descriptor {
        return if (ptr < paging.physical_memory_max)
            self.addressable_space_allocator.frame_from_idx(@truncate(ptr / @sizeOf(paging.page)))
        else
            self.non_addressable_space_allocator.frame_from_idx(@truncate(ptr / @sizeOf(paging.page)));
    }

    pub fn print(self: *Self) void {
        self.addressable_space_allocator.print();
    }
};
