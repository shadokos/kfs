const ft = @import("../ft/ft.zig");
const paging = @import("paging.zig");
const Mapping = @import("mapping.zig");

pub const EarlyVirtualSpaceAllocator = struct {
	address : usize,
	size : usize,

	pub const Error = error{NoSpaceFound};

	const Self = @This();

	// early virtual address space allocator
	pub fn alloc_space(self : *Self, size : usize) Error!usize {
		if(size > 1) {
			@panic("cannot allocate more than one page with early virtual address space allocator");
		}
		const first_dir : paging.dir_idx = @truncate(self.address >> 10); // todo
		const last_dir : paging.dir_idx = first_dir + @as(paging.dir_idx, @intCast(ft.math.divCeil(usize, self.size, 1 << 10) catch unreachable));

		for (paging.page_dir_ptr[first_dir..last_dir], first_dir..) |dir_entry, dir_index| {
			const first_entry : paging.table_idx = @intCast(self.address % (1 << 10));
			var last_entry : usize = @intCast((self.address + self.size) % (1 << 10));
			if (last_entry < first_entry) {
				last_entry = (1 << 10);
			}
			if (dir_entry.present) {
				const table = Mapping.get_table_ptr(@intCast(dir_index));
				for (table[first_entry..last_entry], first_entry..) |table_entry, table_index| {
					if (!Mapping.is_page_mapped(table_entry)) {
						const ret = @as(u32, @bitCast(
							paging.VirtualPtrStruct{
								.dir_index = @intCast(dir_index),
								.table_index = @intCast(table_index),
								.page_index = 0,
							}
						)) / paging.page_size;
						return ret;
					}
				}
			} else {
				const ret = @as(u32, @bitCast(
					paging.VirtualPtrStruct{
						.dir_index = @intCast(dir_index),
						.table_index = first_entry,
						.page_index = 0,
					}
				)) / paging.page_size;
				return ret;
			}
		}
		return Error.NoSpaceFound;
	}
	// noop function, exist just for interface
	pub fn free_space(self : *Self, address : usize, size : usize) Error!void {
		_ = self;
		_ = address;
		_ = size;
	}
};
