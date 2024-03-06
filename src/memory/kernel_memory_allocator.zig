const Slab = @import("slab.zig").Slab;
const Cache = @import("cache.zig").Cache;
const global_cache = &@import("../memory.zig").global_cache;

pub const KernelMemoryAllocator = struct {
	const Self = @This();

	var caches: [14]*Cache = undefined;

	pub fn cache_init() !void {
		const CacheDescription = struct {
			name: []const u8,
			size: usize,
			order: u5,
		};

		const cache_descriptions: [14]CacheDescription = .{
			.{ .name = "kmalloc_4",    .size = 4,     .order = 0 },
			.{ .name = "kmalloc_8",    .size = 8,     .order = 0 },
			.{ .name = "kmalloc_16",   .size = 16,    .order = 0 },
			.{ .name = "kmalloc_32",   .size = 32,    .order = 0 },
			.{ .name = "kmalloc_64",   .size = 64,    .order = 0 },
			.{ .name = "kmalloc_128",  .size = 128,   .order = 0 },
			.{ .name = "kmalloc_256",  .size = 256,   .order = 1 },
			.{ .name = "kmalloc_512",  .size = 512,   .order = 2 },
			.{ .name = "kmalloc_1k",   .size = 1024,  .order = 3 },
			.{ .name = "kmalloc_2k",   .size = 2048,  .order = 3 },
			.{ .name = "kmalloc_4k",   .size = 4096,  .order = 3 },
			.{ .name = "kmalloc_8k",   .size = 8192,  .order = 4 },
			.{ .name = "kmalloc_16k",  .size = 16384, .order = 5 },
			.{ .name = "kmalloc_32k",  .size = 32768, .order = 5 },
		};

		inline for (0..cache_descriptions.len) |i| {
			caches[i] = try global_cache.create(
				cache_descriptions[i].name,
				cache_descriptions[i].size,
				cache_descriptions[i].order
			);
		}
	}

	fn _kmalloc(size: usize) !* align(1) usize {
		return switch(size) {
			0...4 => caches[0].alloc_one(),
			5...8 => caches[1].alloc_one(),
			9...16 => caches[2].alloc_one(),
			17...32 => caches[3].alloc_one(),
			33...64 => caches[4].alloc_one(),
			65...128 => caches[5].alloc_one(),
			129...256 => caches[6].alloc_one(),
			257...512 => caches[7].alloc_one(),
			513...1024 => caches[8].alloc_one(),
			1025...2048 => caches[9].alloc_one(),
			2049...4096 => caches[10].alloc_one(),
			4097...8192 => caches[11].alloc_one(),
			8193...16384 => caches[12].alloc_one(),
			16385...32768 => caches[13].alloc_one(),
			else => Cache.Error.AllocationFailed,
		};
	}

	pub fn alloc(_: *Self, comptime T: type, n: usize) ![]T {
		return @as([*]T, @ptrFromInt(@intFromPtr(try _kmalloc(@sizeOf(T) * n))))[0..n];
	}

	pub fn free(_: *Self, ptr: anytype) void {
		global_cache.cache.free(ptr);
	}

	pub fn obj_size(_: *Self, ptr: anytype) ?usize {
		var pfd = global_cache.cache.get_page_frame_descriptor(ptr);
		var slab: ?*Slab = if (pfd.next) |slab| @ptrCast(@alignCast(slab)) else null;

		if (slab) |s| return if (s.is_obj_in_slab(ptr)) s.header.cache.size_obj else null
		else return null;
	}
};