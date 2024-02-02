const ft = @import("../ft/ft.zig");

/// page index type
pub const idx_t = usize;

/// order type (for buddy allocation)
pub const order_t = ft.meta.Int(.unsigned, ft.math.log2(@typeInfo(idx_t).Int.bits));

/// flags of a page frame
pub const page_flag = packed struct {
	available : bool = false,
};

/// page frame descriptor
pub const page_frame_descriptor = struct {
	flags : page_flag,
	next : ?*page_frame_descriptor = null,
	prev : ?*page_frame_descriptor = null,
	order : u5 = 0,
};

/// page
pub const page = [4096]u8;
