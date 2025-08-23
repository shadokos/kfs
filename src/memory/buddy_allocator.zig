const std = @import("std");
const tty = @import("../tty/tty.zig");
const paging = @import("paging.zig");
const bitmap = @import("../misc/bitmap.zig");
const BitMap = bitmap.UnsafeBitMap;
const printk = @import("../tty/tty.zig").printk;
const multiboot_h = @cImport({
    @cInclude("multiboot.h");
});

const idx_t = paging.idx_t;
const order_t = paging.order_t;
const page_frame_descriptor = paging.page_frame_descriptor;
const page = paging.page;

/// Page allocator using the buddy allocator algorithm, it need an allocator
/// to allocate its data structures and a max order (see https://wiki.osdev.org/Page_Frame_Allocation)
pub fn BuddyAllocator(comptime max_order: order_t) type {
    if (max_order == 0)
        @compileError("max order can't be 0");
    return struct {
        /// the allocator used to allocates data structures for the BuddyAllocator
        allocator: ?std.mem.Allocator = null,

        /// store information about pages (like flags) (mem_map[0] store information for page mem[0])
        mem_map: []page_frame_descriptor = ([0]page_frame_descriptor{})[0..],

        /// see https://wiki.osdev.org/Page_Frame_Allocation
        bit_maps: [max_order + 1]BitMap = undefined,

        /// see https://wiki.osdev.org/Page_Frame_Allocation
        free_lists: [max_order + 1]?*page_frame_descriptor = .{null} ** (max_order + 1),

        /// the total number of pages
        total_pages: usize = 0,

        allocated_pages: usize = 0,

        /// represent a bit in the bit map
        const Bit = bitmap.Bit;

        /// errors that can be returned by allocate
        pub const Error = error{ NotEnoughSpace, DoubleFree, OutOfBounds };

        const Self = @This();

        /// init an instance (if the underlying allocator is set)self.bit_map
        pub fn init(_total_pages: idx_t, _allocator: std.mem.Allocator) Self {
            var self = Self{ .total_pages = _total_pages, .allocator = _allocator };

            self.mem_map = _allocator.alloc(
                page_frame_descriptor,
                self.total_pages,
            ) catch @panic("not enough space to allocate mem_map");
            @memset(self.mem_map, .{ .flags = .{ .available = false } });

            for (0..max_order + 1) |o| {
                const bit_map_size = std.math.divCeil(
                    usize,
                    self.total_pages,
                    @as(usize, 1) << @truncate(o),
                ) catch unreachable;
                self.bit_maps[o] = BitMap.init(@ptrCast(_allocator.alloc(
                    usize,
                    (std.math.divCeil(usize, bit_map_size, 8) catch unreachable),
                ) catch @panic("not enough space to allocate bitmap")), bit_map_size);
                for (0..bit_map_size) |i| self.bit_maps[o].set(i, .Taken) catch unreachable;
            }
            self.allocated_pages = self.total_pages;

            return self;
        }

        /// return the pointer to the frame of the page frame identified by p
        pub inline fn frame_from_idx(self: Self, p: idx_t) *page_frame_descriptor {
            return &self.mem_map[p];
        }

        /// return the id of the page frame described by f
        pub inline fn idx_from_frame(self: Self, f: *page_frame_descriptor) idx_t {
            return ((@intFromPtr(f) - @intFromPtr(&self.mem_map[0])) / @sizeOf(page_frame_descriptor));
        }

        /// set the bit corresponding to the order order of the page frame identified by page_index
        fn set_bit(self: *Self, page_index: idx_t, order: order_t, bit: Bit) void {
            self.bit_maps[order].set(page_index >> order, bit) catch unreachable;
        }

        /// return a the bit corresponding to the order order of the page frame identified by page_index
        fn get_bit(self: *Self, page_index: idx_t, order: order_t) Bit {
            return self.bit_maps[order].get(page_index >> order) catch .Taken;
        }

        /// return a pointer to the bit corresponding to the order of the buddy of the
        /// page frame identified by page_index
        inline fn buddy(page_index: idx_t, order: order_t) idx_t {
            return page_index ^ (@as(idx_t, 1) << order);
        }

        /// return the base buddy of the order order of the page frame identified by page_index
        inline fn base_buddy(page_index: idx_t, order: order_t) idx_t {
            return page_index & ~(@as(idx_t, 1) << order);
        }

        /// remove the page frame identified by page_idx from the list of free pages for order order
        fn lst_remove(self: *Self, order: order_t, page_idx: idx_t) void {
            const frame = self.frame_from_idx(
                std.mem.alignBackward(idx_t, page_idx, @as(idx_t, 1) << order),
            );

            if (frame.prev) |prev| {
                prev.next = frame.next;
            } else {
                self.free_lists[order] = frame.next;
            }
            if (frame.next) |next| {
                next.prev = frame.prev;
            }
            frame.prev = null;
            frame.next = null;
        }

        /// add the page frame identified by page_idx to the list of free pages for order order
        fn lst_add(self: *Self, order: order_t, page_idx: idx_t) void {
            const frame = self.frame_from_idx(
                std.mem.alignBackward(idx_t, page_idx, @as(idx_t, 1) << order),
            );

            frame.prev = null;
            frame.next = self.free_lists[order];
            if (frame.next) |next| {
                next.prev = frame;
            }
            self.free_lists[order] = frame;
        }

        /// break a page for order order
        /// (if everything go fine, after this call, at least one page is free at order order)
        fn break_for(self: *Self, order: order_t) Error!void {
            if (self.free_lists[order] != null)
                return;
            if (order >= max_order)
                return Error.NotEnoughSpace;
            if (order < max_order)
                try self.break_for(order + 1);
            if (self.free_lists[order + 1]) |bigger| {
                const idx = self.idx_from_frame(bigger);
                self.lst_remove(order + 1, idx);
                self.set_bit(idx, order + 1, .Taken);
                self.lst_add(order, idx);
                self.set_bit(idx, order, .Free);
                self.lst_add(order, buddy(idx, order));
                self.set_bit(buddy(idx, order), order, .Free);
            } else {
                return Error.NotEnoughSpace;
            }
        }

        /// free one page previously allocated with alloc_page_block on the same allocator instance
        pub fn free_page(self: *Self, page_index: idx_t) Error!void {
            // double free detection, do we want that in release mode?
            for (0..max_order) |o| {
                if (self.get_bit(page_index, @truncate(o)) == .Free) {
                    return Error.DoubleFree;
                }
            }

            var order: order_t = 0;
            var page_idx: idx_t = page_index;
            var buddy_idx: idx_t = buddy(page_index, order);

            while (self.get_bit(buddy_idx, order) == .Free and
                order < max_order) : (buddy_idx = buddy(page_index, order))
            {
                self.set_bit(buddy_idx, order, .Taken);
                self.lst_remove(order, buddy_idx);
                if (base_buddy(page_idx, order) == buddy_idx) {
                    page_idx = buddy_idx;
                }
                order += 1;
            } else if (self.get_bit(buddy_idx, order) == .Taken) {
                self.set_bit(page_idx, order, .Free);
                self.lst_add(order, page_idx);
            }
            self.allocated_pages -= 1;
        }

        /// alloc n physical pages and return the idx of the first page
        pub fn alloc_pages(self: *Self, n: usize) Error!idx_t {
            var order: order_t = @intCast(std.math.log2(n));
            if (@as(usize, 1) << order < n) {
                order += 1;
            }
            if (order > max_order)
                return Error.NotEnoughSpace;

            try self.break_for(order);
            if (self.free_lists[order]) |p| {
                self.allocated_pages += @as(usize, 1) << order;
                const idx = self.idx_from_frame(p);
                self.lst_remove(order, idx);
                self.set_bit(idx, order, .Taken);

                const actual_size = @as(usize, 1) << order;
                if (n != actual_size) {
                    for ((idx + n)..(idx + actual_size)) |i| {
                        self.free_page(i) catch unreachable;
                    }
                }
                return idx;
            } else unreachable;
        }

        /// alloc n physical pages and return the idx of the first page, try to allocate the pages at `hint`
        pub fn alloc_pages_hint(self: *Self, hint: idx_t, n: usize) Error!idx_t {
            _ = hint; // todo: hints
            return self.alloc_pages(n);
        }

        /// free `n` pages starting at `first`
        pub fn free_pages(self: *Self, first: idx_t, n: usize) !void {
            if (first +| n > self.total_pages)
                return Error.OutOfBounds;
            // todo: maybe optimize this
            for (first..(first +| n)) |p| {
                try self.free_page(p);
            }
        }

        /// set the underlying allocator
        pub fn set_allocator(self: *Self, allocator: std.mem.Allocator) void {
            self.allocator = allocator;
        }

        /// return the size in bits of the bitmap needed to describe pages page frames
        fn bitmap_size(pages: usize) usize {
            var ret: usize = 0;
            for (0..max_order + 1) |o| {
                ret += std.math.divCeil(
                    usize,
                    pages,
                    @as(usize, 1) << @truncate(o),
                ) catch unreachable;
            }
            return ret;
        }

        /// return the max possible space descriptible with the space available in the undelying allocator
        pub fn max_possible_space(comptime T: type, available_space: usize) T {
            const average_page_cost: usize = @bitSizeOf(page_frame_descriptor) + 2;

            var ret: usize = std.math.divCeil(
                usize,
                available_space * 8,
                average_page_cost,
            ) catch unreachable;
            while (@sizeOf(page_frame_descriptor) * ret + (std.math.divCeil(
                usize,
                bitmap_size(ret),
                8,
            ) catch 0) > available_space) {
                ret -= 1;
            }
            return @as(T, @intCast(ret)) * @sizeOf(page);
        }

        /// return the size needed for a page frame allocator on `pages` pages
        pub fn size_for(pages: usize) usize {
            return bitmap_size(pages) + pages * @sizeOf(page_frame_descriptor);
        }

        /// print the bitmap from from to to in the main tty
        pub fn print_bitmap(self: *Self, from: idx_t, to: idx_t) void {
            var line: idx_t = from;
            while (line < to) : (line += tty.width) {
                for (0..max_order + 1) |o| {
                    var array: [tty.width]u8 = undefined;
                    for (0..tty.width) |c| {
                        if (c + line < to and (o == 0 or ((line + c) % (@as(usize, 1) << @intCast(o)) == 0))) {
                            array[c] = switch (self.get_bit(line + c, @intCast(o))) {
                                .Taken => '0',
                                .Free => '1',
                            };
                        } else {
                            array[c] = ' ';
                        }
                    }
                    printk("{s}", .{array[0..tty.width]});
                }
                printk("\n", .{});
            }
        }

        /// print the free lists using printk
        pub fn print(self: *Self) void {
            printk("allocated pages : {}/{}\n", .{ self.allocated_pages, self.total_pages });
        }
    };
}
