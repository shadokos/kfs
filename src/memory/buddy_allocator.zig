// const boot = @import("boot.zig");
const ft = @import("../ft/ft.zig");
const tty = @import("../tty/tty.zig");
const paging = @import("paging.zig");
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
		mem_map : []page_frame_descriptor = undefined,

		/// see https://wiki.osdev.org/Page_Frame_Allocation
		bit_map : []Bit = undefined,

		/// see https://wiki.osdev.org/Page_Frame_Allocation
		free_lists : [max_order + 1] ?*page_frame_descriptor = .{null} ** (max_order + 1),

		/// the total number of pages
		total_pages : usize = undefined,

		/// represent a bit in the bit map
		const Bit = enum(u1) {
			Taken,
			Free,
		};

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

		/// return a pointer to the bit corresponding to the order order of the page frame identified by page_index
		inline fn bit(self : Self, page_index : idx_t, order : order_t) *Bit {
			const t : u64 = self.total_pages;
			const o : order_t = order;
			const m : order_t = max_order;
			return &self.bit_map[@intCast((page_index >> o) + (t / (@as(usize, 1) << (max_order + 1))) * (((@as(usize, 1) << (o + 1)) - 1) << (m - o)))];
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
			if (self.free_lists[order] != null)
				return ;
			if (order < max_order)
				try self.break_for(order + 1);
			if (self.free_lists[order + 1]) |bigger| {
				const idx = self.idx_from_frame(bigger);
				self.lst_remove(order + 1, idx);
				self.bit(idx, order + 1).* = .Taken;
				self.lst_add(order, idx);
				self.bit(idx, order).* = .Free;
				self.lst_add(order, buddy(idx, order));
				self.bit(buddy(idx, order), order).* = .Free;
			} else {
				return Error.NotEnoughSpace;
			}
		}

		/// allocate one page of order order
		pub fn alloc_page(self : *Self, order : order_t) Error!idx_t {
			try self.break_for(order);
			if (self.free_lists[order]) |p| {
				const idx = self.idx_from_frame(p);
				self.lst_remove(order, idx);
				self.bit(idx, order).* = .Taken;
				p.order = order;
				return idx;
			} else unreachable;
		}

		/// free one page previously allocated with alloc_page on the same allocator instance
		pub fn free_page(self : *Self, page_index : idx_t) void {
			var frame : *page_frame_descriptor = self.frame_from_idx(page_index);
			var order : order_t = frame.order;
			var page_idx : idx_t = page_index;
			var buddy_idx : idx_t = buddy(page_index, order);

			if (self.bit(page_idx, order).* == .Free)
				@panic("double free in free_page");

			while (self.bit(buddy_idx, order).* == .Free and order < max_order) : (buddy_idx = buddy(page_index, order)) {
				self.bit(buddy_idx, order).* = .Taken;
				if (base_buddy(page_idx, order) == page_idx) {
					self.lst_remove(order, buddy_idx);
				} else {
					self.lst_remove(order, page_idx);
					page_idx = buddy_idx;
				}
				order += 1;
			} else {
				self.bit(page_idx, order).* = .Free;
				self.lst_add(order, page_idx);
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
				const average_page_cost : f32 = @sizeOf(page_frame_descriptor) + (((@as(idx_t, 1) << max_order) - 1) / max_order) / 8;

				var ret : usize = @intFromFloat(@as(f32, @floatFromInt(available_space)) / average_page_cost);
				while (@sizeOf(page_frame_descriptor) * ret + (ft.math.divCeil(usize, bitmap_size(ret), 8) catch 0) > available_space) {
					ret -= 1;
				}
				return @as(T, @intCast(ret)) * @sizeOf(page);
			}
			else @panic("no allocator!");
		}

		/// init an instance (if the underlying allocator is set)
		pub fn init(self : *Self, _total_pages : idx_t) void {
			self.total_pages = _total_pages;

			if (self.total_pages == 0)
				@panic("not enough space to boot");
			if (self.allocator) |a| {
				self.mem_map = a.alloc(page_frame_descriptor, self.total_pages) catch @panic("not enough space to allocate mem_map");
				@memset(self.mem_map, .{.flags = .{.available = false}});

				self.bit_map = a.alloc(Bit, bitmap_size(self.total_pages)) catch @panic("not enough space to allocate bitmap");
				@memset(@as([*]align(1) usize, @ptrFromInt(@intFromPtr(self.bit_map.ptr)))[0..(ft.math.divCeil(usize, self.bit_map.len, 32) catch 0)], 0);
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
							printk("{b}", .{@intFromEnum(self.bit(line + c, @intCast(o)).*)});
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