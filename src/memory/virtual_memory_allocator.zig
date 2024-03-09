const ft = @import("../ft/ft.zig");
const paging = @import("paging.zig");

/// allocator for virtually contiguous memory (equivalent to linux's vmalloc)
pub fn VirtualMemoryAllocator(comptime PageAllocator : type) type {
	return struct {
		/// underlying page allocator
		pageAllocator : *PageAllocator,

		/// header of a chunk
		const ChunkHeader = packed struct {
			npages : usize,
		};

		pub const Error = PageAllocator.Error;

		const Self = @This();

		/// init the allocator
		pub fn init(_pageAllocator : *PageAllocator) Self {
			var self = Self{.pageAllocator = _pageAllocator};
			return self;
		}

		/// allocate virtually contiguous memory
		pub fn alloc(self: *Self, comptime T: type, n: usize) ![]T { // todo: specify error
			const npages = ft.math.divCeil(usize, @sizeOf(ChunkHeader) + @sizeOf(T) * n, paging.page_size) catch unreachable;
			const chunk : *ChunkHeader = @ptrCast(@alignCast(try self.pageAllocator.alloc_pages_opt(npages, .{.physically_contiguous = false})));
			chunk.npages = npages;

			return @as([*]T, @ptrFromInt(@intFromPtr(chunk) + @sizeOf(ChunkHeader)))[0..n];
		}

		/// free memory previously allocated with alloc()
		pub fn free(self: *Self, arg: anytype) void {
			const chunk : *ChunkHeader = @ptrFromInt(@as(usize, @intFromPtr(arg)) - @sizeOf(ChunkHeader));

			self.pageAllocator.free_pages(@ptrCast(@alignCast(chunk)), chunk.npages) catch |e| {
				@import("../tty/tty.zig").printk("error: {s}\n", .{@errorName(e)});
				@panic("invalid free");
			};
		}
	};
}