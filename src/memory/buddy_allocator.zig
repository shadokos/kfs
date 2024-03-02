// const boot = @import("boot.zig");
const ft = @import("../ft/ft.zig");
const tty = @import("../tty/tty.zig");
const paging = @import("paging.zig");
const bitmap = @import("bitmap.zig");
const printk = @import("../tty/tty.zig").printk;
const multiboot_h = @cImport({ @cInclude("multiboot.h"); });

const idx_t = paging.idx_t;
const order_t = paging.order_t;
const page_frame_descriptor = paging.page_frame_descriptor;
const page = paging.page;

/// Page allocator using the buddy allocator algorithm, it need an allocator
/// to allocate its data structures and a max order (see https://wiki.osdev.org/Page_Frame_Allocation)
pub fn BuddyAllocator(comptime AllocatorType : type, comptime max_order : order_t) type {
	if (max_order == 0)
		@compileError("max order can't be 0");
	return struct {
		/// the allocator used to allocates data structures for the BuddyAllocator
		allocator : ?*AllocatorType = null,

		/// store information about pages (like flags) (mem_map[0] store information for page mem[0])
		mem_map : []page_frame_descriptor = ([0]page_frame_descriptor{})[0..],

		/// see https://wiki.osdev.org/Page_Frame_Allocation
		bit_map : bitmap.BitMap = undefined,

		/// see https://wiki.osdev.org/Page_Frame_Allocation
		free_lists : [max_order + 1] ?*page_frame_descriptor = .{null} ** (max_order + 1),

		/// the total number of pages
		total_pages : usize = 0,

		/// represent a bit in the bit map
		const Bit = bitmap.Bit;

		/// errors that can be returned by allocate
		pub const Error = error{NotEnoughSpace};

		const Self = @This();

		/// return the pointer to the frame of the page frame identified by p
		pub inline fn frame_from_idx(self : Self, p : idx_t) *page_frame_descriptor {
			return &self.mem_map[p];
		}

		/// return the id of the page frame described by f
		pub inline fn idx_from_frame(self : Self, f : *page_frame_descriptor) idx_t {
			return ((@intFromPtr(f) - @intFromPtr(&self.mem_map[0])) / @sizeOf(page_frame_descriptor));
		}

		/// set the bit corresponding to the order order of the page frame identified by page_index
		fn set_bit(self : *Self, page_index : idx_t, order : order_t, bit : Bit) void {
			const t : u64 = self.total_pages;
			const o : order_t = order;
			const m : order_t = max_order;
			self.bit_map.set(@intCast((page_index >> o) + (t / (@as(usize, 1) << (max_order + 1))) * (((@as(usize, 1) << (o + 1)) - 1) << (m - o))), bit) catch unreachable;
		}

		/// return a the bit corresponding to the order order of the page frame identified by page_index
		fn get_bit(self : *Self, page_index : idx_t, order : order_t) Bit {
			const t : u64 = self.total_pages;
			const o : order_t = order;
			const m : order_t = max_order;
			// self.bit_map.get(@intCast((page_index >> o) + (t / (@as(usize, 1) << (max_order + 1))) * (((@as(usize, 1) << (o + 1)) - 1) << (m - o)))) catch unreachable,
			// @intFromEnum(self.bit_map.get(@intCast((page_index >> o) + (t / (@as(usize, 1) << (max_order + 1))) * (((@as(usize, 1) << (o + 1)) - 1) << (m - o)))) catch unreachable)
			// });
			return self.bit_map.get(@intCast((page_index >> o) + (t / (@as(usize, 1) << (max_order + 1))) * (((@as(usize, 1) << (o + 1)) - 1) << (m - o)))) catch unreachable;
		}

		/// return a pointer to the bit corresponding to the order order of the buddy of the page frame identified by page_index
		inline fn buddy(page_index : idx_t, order : order_t) idx_t {
			return page_index ^ (@as(idx_t, 1) << order);
		}

		/// return the base buddy of the order order of the page frame identified by page_index
		inline fn base_buddy(page_index : idx_t, order : order_t) idx_t {
			return page_index & ~(@as(idx_t, 1) << order);
		}

		/// remove the page frame identified by page_idx from the list of free pages for order order
		fn lst_remove(self : *Self, order : order_t, page_idx : idx_t) void {
			const frame = self.frame_from_idx(page_idx & ~((@as(idx_t, 1) << order) - 1));
			if (frame.prev) |prev| {
				prev.next = frame.next;
			}
			else {
				self.free_lists[order] = frame.next;
			}
			if (frame.next) |next| {
				next.prev = frame.prev;
			}
			frame.prev = null;
			frame.next = null;
		}

		/// add the page frame identified by page_idx to the list of free pages for order order
		fn lst_add(self : *Self, order : order_t, page_idx : idx_t) void {
			const frame = self.frame_from_idx(page_idx & ~((@as(idx_t, 1) << order) - 1));

			frame.next = self.free_lists[order];
			self.free_lists[order] = frame;
		}

		/// break a page for order order (if everything go fine, after this call, at least one page is free at order order)
		fn break_for(self : *Self, order : order_t) Error!void {
			if (self.free_lists[order] != null or order == max_order)
				return ;
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
		pub fn free_page(self : *Self, page_index : idx_t) !void {
			var order : order_t = 0;
			var page_idx : idx_t = page_index;
			var buddy_idx : idx_t = buddy(page_index, order);


			// double free detection, do we want that in release mode?
			for (0..max_order) |o| {
				if (self.get_bit(page_idx, @truncate(o)) == .Free) {
					@panic("double free in free_page_block"); // todo error
				}
			}

			while (self.get_bit(buddy_idx, order) == .Free and order < max_order) : (buddy_idx = buddy(page_index, order)) {
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
		}

		pub fn alloc_pages(self : *Self, n : usize) Error!idx_t {
			var order : order_t = @intCast(ft.math.log2(n));
			if (@as(usize, 1) << order < n) {
				order += 1;
			}

			try self.break_for(order);
			if (self.free_lists[order]) |p| {
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

		pub fn alloc_pages_hint(self : *Self, hint : idx_t, n : usize) Error!idx_t {
			_ = hint; // todo: hints
			return self.alloc_pages(n);
		}

		pub fn free_pages(self : *Self, first : idx_t, n : usize) !void { // todo: check out of bound
			// todo: maybe optimize this
			for (first..(first + n)) |p| {
				try self.free_page(p);
			}
		}

		/// set the underlying allocator
		pub fn set_allocator(self : *Self, allocator : *AllocatorType) void {
			self.allocator = allocator;
		}

		/// return the size of the bitmap needed to describe pages page frames
		fn bitmap_size(pages : usize) usize {
			// const average_page_cost : f32 = @as(f32, @floatFromInt((@as(usize, 1) << (max_order + 1)) - 1)) / @as(f32, @floatFromInt(@as(usize, 1) << (max_order)));
			const average_page_cost : f32 = 2;

			var ret : usize = @intFromFloat(@as(f32, @floatFromInt(ft.mem.alignForward(usize, pages, @as(usize, 1) << (max_order + 1)))) * average_page_cost);
			// var ret : usize = @intFromFloat(@as(f32, @floatFromInt(pages - (pages % (@as(usize, 1) << (max_order + 1))))) * average_page_cost);

			// for (0..(pages % (@as(usize, 1) << (max_order + 1)))) |i| {
			// 	ret += @min(@clz(i) + 1, max_order + 1);
			// }
			return ret;
		}

		/// return the max possible space descriptible with the space available in the undelying allocator
		pub fn max_possible_space(self : *Self, comptime T: type) T {
			if (self.allocator) |a| {
				const available_space = a.remaining_space();
				// const average_page_cost : f32 = @sizeOf(page_frame_descriptor) + (((@as(idx_t, 1) << max_order) - 1) / max_order) / 8;
				const average_page_cost : f32 = @sizeOf(page_frame_descriptor) + 0.25;

				var ret : usize = @intFromFloat(@as(f32, @floatFromInt(available_space)) / average_page_cost);
				while (@sizeOf(page_frame_descriptor) * ret + (ft.math.divCeil(usize, bitmap_size(ret), 8) catch 0) > available_space) {
					ret -= 1;
				}
				return @as(T, @intCast(ret)) * @sizeOf(page);
			}
			else @panic("no allocator!");
		}

		pub fn size_for(pages : usize) usize {
			return bitmap_size(pages) + pages * @sizeOf(page_frame_descriptor);
		}

		/// init an instance (if the underlying allocator is set)self.bit_map
		pub fn init(self : *Self, _total_pages : idx_t) void {
			self.total_pages = _total_pages;

			if (self.total_pages == 0)
				@panic("not enough space to boot");
			if (self.allocator) |a| {
				self.mem_map = a.alloc(page_frame_descriptor, self.total_pages) catch @panic("not enough space to allocate mem_map");
				@memset(self.mem_map, .{.flags = .{.available = false}});
				const size = bitmap_size(self.total_pages);
				self.bit_map = bitmap.BitMap.init(@ptrCast(a.alloc(usize, bitmap.BitMap.compute_len(size)) catch @panic("not enough space to allocate bitmap")), size);
				for (0..size) |i| self.bit_map.set(i, .Taken) catch unreachable;
			}
			else @panic("no allocator!");
		}

		/// print the bitmap from from to to in the main tty
		pub fn print_bitmap(self : *Self, from : idx_t, to : idx_t) void {
			var line : idx_t = from;
			while (line < to) : (line += tty.width)
			{
				for (0..max_order + 1) |o| {
					for (0..tty.width) |c| {
						if (c + line < to and (o == 0 or ((line + c) % (@as(usize, 1) << @intCast(o)) == 0))) {
							printk("{b}", .{@intFromEnum(self.get_bit(line + c, @intCast(o)))});
						} else {
							printk(" ", .{});
						}
					}
				}
				printk("\n", .{});
			}
		}
	};
}