const ft = @import("../ft/ft.zig");
const printk = @import("../tty/tty.zig").printk;
const VirtualPageAllocatorType = @import("../memory.zig").VirtualPageAllocatorType;
const PAGE_SIZE: usize = 4096;
const CACHE_NAME_LEN = 15;
const BitMap = @import("bitmap.zig").BitMap;
const Bit = @import("bitmap.zig").Bit;

pub const SlabState = enum {
	Empty,
	Partial,
	Full,
};

pub const SlabHeader = struct {
	cache: *Cache = undefined,
	next: ?*Slab = null,
	prev: ?*Slab = null,
	in_use: usize = 0,
	next_free: ?u16 = 0,
};

pub const Slab = struct {
	const Self = @This();

	pub const Error = error{ SlabFull, SlabCorrupted, OutOfBounds, InvalidOrder, InvalidSize };

	header: SlabHeader = SlabHeader{},

	bitmap: BitMap = BitMap{},
	data: []?u16 = undefined,

	pub fn init(cache: *Cache, page: *usize) Slab {
		var new = Slab{ .header = .{ .cache = cache } };

		var mem: [*]usize = @ptrFromInt(@intFromPtr(page) + @sizeOf(Slab));
		new.bitmap = BitMap.init(mem, cache.obj_per_slab);

		var start = @intFromPtr(page) + @sizeOf(Slab) + new.bitmap.get_size();
		new.data = @as([*]?u16, @ptrFromInt(start))[0..cache.obj_per_slab * (cache.size_obj / @sizeOf(usize))];

		for (0..cache.obj_per_slab) |i| {
			new.data[i * (cache.size_obj / @sizeOf(usize))] =
				if (i + 1 < cache.obj_per_slab) @truncate(i + 1) else null;
		}
		return new;
	}

	pub fn alloc_object(self: *Self) Error!*usize {
		const next = self.header.next_free orelse return Error.SlabFull;
		self.bitmap.set(next, Bit.Taken) catch return Error.SlabCorrupted;

		const index = next * (self.header.cache.size_obj / @sizeOf(usize));
		switch (self.get_state()) {
			.Empty => self.header.cache.move_slab(self, .Partial),
			.Partial => if (self.data[index] == null) self.header.cache.move_slab(self, .Full),
			.Full => unreachable,
		}
		self.header.next_free = self.data[index];
		self.header.in_use += 1;
		return @ptrCast(@alignCast(&self.data[index]));
	}

	pub fn free_object(self: *Self, obj: *usize) void {
		const obj_addr = @intFromPtr(obj);
		if (obj_addr < @intFromPtr(&self.data[0]) or obj_addr > @intFromPtr(&self.data[self.data.len - 1]))
			@panic("SLAB: TODO Out of bounds Error"); // TODO: Error
		if ((obj_addr - @intFromPtr(&self.data[0])) % self.header.cache.size_obj != 0)
			@panic("SLAB: TODO Not aligned Error"); // TODO: Error

		//printk("free object: 0x{x}\n", .{obj_addr});
		const index: u16 = @truncate((obj_addr - @intFromPtr(&self.data[0])) / self.header.cache.size_obj);
		//printk("index: {d}\n", .{index});
		if (self.bitmap.get(index) catch .Free == .Free) @panic("SLAB: TODO Double free detected"); // TODO: Error
		//printk("{}\n", .{self.bitmap.get(index) catch .Free});
		self.bitmap.set(index, Bit.Free) catch @panic("SLAB: TODO bitmap error"); // TODO: Error
		//printk("{}\n", .{self.bitmap.get(index) catch .Free});
		//printk("state: {}\n", .{self.get_state()});
		switch (self.get_state()) {
			.Empty => unreachable,
			.Partial => if (self.header.in_use == 1) self.header.cache.move_slab(self, .Empty),
			.Full => self.header.cache.move_slab(self, .Partial),
		}
		self.header.in_use -= 1;
		self.data[index * (self.header.cache.size_obj / @sizeOf(usize))] = self.header.next_free;
		self.header.next_free = index;
	}

	pub fn get_state(self: *Self) SlabState {
		if (self.header.next_free == null) return .Full;
		if (self.header.in_use == 0) return .Empty;
		return .Partial;
	}

	pub fn debug(self: *Self) void {
		printk("self: 0x{x}\n", .{@intFromPtr(self)});
		printk("Slab Header:\n", .{});
		inline for (@typeInfo(SlabHeader).Struct.fields) |field|
			printk("  header.{s}: 0x{x} ({d} bytes)\n", .{field.name, @intFromPtr(&@field(self.header, field.name)), @sizeOf(field.type)});

		printk("Bitmap:\n", .{});
		inline for (@typeInfo(BitMap).Struct.fields) |field|
			printk("  bitmap.{s}: 0x{x} ({d} bytes)\n", .{field.name, @intFromPtr(&@field(self.bitmap, field.name)), @sizeOf(field.type)});

		printk("Data:\n", .{});
		printk("  data: 0x{x} ({d} bytes)\n", .{@intFromPtr(&self.data[0]), @sizeOf(@TypeOf(self.data))});

		printk("Values:\n", .{});
		if (self.header.next_free) |next_free| printk("  next_free: {d}\n", .{next_free}) else printk("  next_free: null\n", .{});
		printk("  cache: 0x{x}\n", .{@intFromPtr(self.header.cache)});
		if (self.header.next) |next| printk("  next: 0x{x}\n", .{@intFromPtr(next)}) else printk("  next: null\n", .{});
		if (self.header.prev) |prev| printk("  prev: 0x{x}\n", .{@intFromPtr(prev)}) else printk("  prev: null\n", .{});
		printk("  in_use: {d}\n", .{self.header.in_use});
		printk("  state: {d}\n", .{self.get_state()});
		printk("\n", .{});
	}
};

pub const Cache = struct {
	const Self = @This();
	const Error = error{ InitializationFailed, AllocationFailed };

	next: ?*Cache = null,
	prev: ?*Cache = null,
	slab_full:	?*Slab = null,
	slab_partial: ?*Slab = null,
	slab_empty: ?*Slab = null,
	allocator: *VirtualPageAllocatorType = undefined,
	pages_per_slab: usize = 0,
	name: [CACHE_NAME_LEN]u8 = undefined,
	nb_slab: usize = 0,
	nb_active_slab: usize = 0,
	obj_per_slab: u16 = 0,
	size_obj: usize = 0,

	pub fn init(
		name: []const u8,
		allocator : *VirtualPageAllocatorType,
		obj_size: usize,
		order: u5
	) Error!Cache {
		var new = Cache{
			.allocator = allocator,
			.pages_per_slab = @as(usize, 1) << order,
			// align the size of the object with usize
			.size_obj = ft.mem.alignForward(usize, obj_size, @sizeOf(usize)),
		};

		// Compute the available space for the slab ((page_size * 2^order) - sise of slab header)
		const available = (PAGE_SIZE * new.pages_per_slab) - @sizeOf(Self);

		new.obj_per_slab = 0;
		while (true) {
			const bitmap_size = BitMap.compute_size(new.obj_per_slab + 1);
			const total_size = bitmap_size + ((new.obj_per_slab + 1) * new.size_obj);
			if (total_size > available) break;
			new.obj_per_slab += 1;
		}
		if (new.obj_per_slab == 0 or new.obj_per_slab >= (1 << 16))
			return Error.InitializationFailed;

		const name_len = @min(name.len, CACHE_NAME_LEN);
		@memset(new.name[0..CACHE_NAME_LEN], 0);
		@memcpy(new.name[0..name_len], name[0..name_len]);
		//new.debug();
		return new;
	}

	pub fn grow(self: *Self, nb_slab: usize) Error!void {
		for (0..nb_slab) |_| {
			var obj = self.allocator.alloc_pages(self.pages_per_slab) catch return Error.AllocationFailed;
			var slab: *Slab = @ptrCast(@alignCast(obj));

			slab.* = Slab.init(self, @ptrCast(obj));

			for (0..self.pages_per_slab) |i| {
				const page_addr = @as(usize, @intFromPtr(obj)) + (i * PAGE_SIZE);
				//printk("init page: 0x{x}\n", .{page_addr});
				var page_descriptor = self.allocator.get_page_frame_descriptor(@ptrFromInt(page_addr));
				page_descriptor.prev = @ptrCast(@alignCast(self));
				page_descriptor.next = @ptrCast(@alignCast(slab));
			}
			self.move_slab(slab, SlabState.Empty);
			self.nb_slab += 1;
		}
	}

	pub fn shrink(self: *Self) void {
		while (self.slab_empty) |slab| {
			self.unlink(slab);
			self.allocator.free_pages(@ptrCast(@alignCast(slab)), self.pages_per_slab) catch unreachable;
			self.nb_slab -= 1;
			printk("free slab: 0x{x}\n", .{@intFromPtr(slab)});
		}
	}

	fn unlink(self: *Self, slab: *Slab) void {
		if (slab.header.prev) |prev| prev.header.next = slab.header.next else switch (slab.get_state()) {
			.Empty => self.slab_empty = slab.header.next,
			.Partial => self.slab_partial = slab.header.next,
			.Full => self.slab_full = slab.header.next,
		}
		if (slab.header.next) |next| next.header.prev = slab.header.prev;
	}

	fn link(self: *Self, slab: *Slab, state: SlabState) void {
		switch (state) {
			.Empty => {
				slab.header.next = self.slab_empty;
				self.slab_empty = slab;
			},
			.Partial => {
				slab.header.next = self.slab_partial;
				self.slab_partial = slab;
			},
			.Full => {
				slab.header.next = self.slab_full;
				self.slab_full = slab;
			},
		}
		if (slab.header.next) |next| next.header.prev = slab;
		slab.header.prev = null;
	}

	pub fn move_slab(self: *Self, slab: *Slab, state: SlabState) void {
		if (state == slab.get_state()) return; // TODO error
		//printk("\x1b[33mcache: 0x{x}: move slab: 0x{x} ({}) -> {}\x1b[0m\n", .{@intFromPtr(self), @intFromPtr(slab), slab.get_state(), state});
		self.unlink(slab);
		self.link(slab, state);
	}

	pub fn alloc_one(self: *Self) Error!*usize {
		var slab: ?*Slab = if (self.slab_partial) |slab| slab else if (self.slab_empty) |slab| slab else null;
		if (slab) |s|
			return s.alloc_object() catch Error.AllocationFailed
		else {
			self.grow(1) catch return Error.AllocationFailed;
			return self.alloc_one();
		}
	}

	pub fn free(self: *Self, ptr: *usize) void {
		const addr = ft.mem.alignBackward(usize, @intFromPtr(ptr), PAGE_SIZE);
		const page_descriptor = self.allocator.get_page_frame_descriptor(@ptrFromInt(addr));

		//printk("cache: 0x{x}\n", .{@intFromPtr(page_descriptor.prev)});
		//printk("slab: 0x{x}\n", .{@intFromPtr(page_descriptor.next)});
		const slab: *Slab = @ptrCast(@alignCast(page_descriptor.next));
		slab.free_object(ptr);
	}

	pub fn create(name: []const u8, obj_size: usize, order: u5) Error!*Cache {
		var cache: *Cache = @ptrCast(@alignCast(global_cache.alloc_one() catch |e| return e));

		cache.* = Cache.init(
			name, global_cache.allocator, obj_size, order
		) catch @panic("Failed to initialize cache");

		cache.next = global_cache.next;
		if (global_cache.next) |next| next.prev = cache;
		global_cache.next = cache;
		return cache;
	}

	pub fn destroy(cache: *Cache) void {
		cache.shrink();
		var lst: ?*Slab = cache.slab_full;

		while (lst) |slab| {
			lst = slab.header.next;
			cache.allocator.free_pages(@ptrCast(@alignCast(slab)), cache.pages_per_slab) catch unreachable;
		}
		lst = cache.slab_partial;
		while (lst) |slab| {
			lst = slab.header.next;
			cache.allocator.free_pages(@ptrCast(@alignCast(slab)), cache.pages_per_slab) catch unreachable;
		}
		if (cache.prev) |prev| prev.next = cache.next else global_cache.next = cache.next;
		if (cache.next) |next| next.prev = cache.prev;
		global_cache.free(@ptrCast(cache));
	}

	fn get_page_descriptor(self: *Self) *Slab {
		return self.allocator.get_page_frame_descriptor(ft.mem.alignBackward(*usize, self, PAGE_SIZE));
	}

	pub fn debug(self: *Self) void {
		var nb_slab_empty: usize = 0;
		var nb_slab_partial: usize = 0;
		var nb_slab_full: usize = 0;
		var object_in_use: usize = 0;

		var head: ?*Slab = self.slab_empty;
		while (head) |slab| : (nb_slab_empty += 1) head = slab.header.next;
		head = self.slab_partial;
		while (head) |slab| : (nb_slab_partial += 1) {
			head = slab.header.next;
			object_in_use += slab.header.in_use;
		}
		head = self.slab_full;
		while (head) |slab| : (nb_slab_full += 1) head = slab.header.next;

		object_in_use += (nb_slab_full * self.obj_per_slab);

		var name_len: usize = 1;
		for (self.name) |c| { if (c == 0) break else name_len += 1; }
		printk("\x1b[31m{s}\x1b[0m: ", .{self.name});
		for (name_len..@max(name_len, CACHE_NAME_LEN)) |_| printk(" ", .{});
		printk("{d: >5} ", .{self.size_obj});
		printk("{d: >5} ", .{self.obj_per_slab});
		printk("{d: >5} ", .{object_in_use});
		printk("{d: >5}  ", .{self.pages_per_slab});
		printk("{d: >5}  ", .{self.nb_slab});
		printk("{d: >5}  ", .{nb_slab_empty});
		printk("{d: >5} ", .{nb_slab_partial});
		printk("{d: >5} ", .{nb_slab_full});
		printk("\n", .{});
		// head = self.slab_empty;
		// if (nb_slab_empty > 0) printk("  \x1b[33mempty: \x1b[0m\n", .{});
		// while (head) |slab| : (head = slab.header.next) slab.debug();
		// head = self.slab_partial;
		// if (nb_slab_partial > 0) printk("  \x1b[33mpartial: \x1b[0m\n", .{});
		// while (head) |slab| : (head = slab.header.next) slab.debug();
		// head = self.slab_full;
		// if (nb_slab_full > 0) printk("  \x1b[33mfull: \x1b[0m\n", .{});
		// while (head) |slab| : (head = slab.header.next) slab.debug();
	}
};

pub var global_cache: Cache = .{};
var kmalloc_caches: [14]*Cache = undefined;

pub fn global_cache_init(allocator: *VirtualPageAllocatorType) void {
	printk("global_cache_init\n", .{});
	global_cache = Cache.init(
		"cache", allocator, @sizeOf(Cache), 0
	) catch @panic("Failed to initialize global_cache");

 	kmalloc_caches[0]  = Cache.create("kmalloc_4",    4,     0) catch @panic("Failed to allocate kmalloc_4 cache");
	kmalloc_caches[1]  = Cache.create("kmalloc_8",    8,     0) catch @panic("Failed to allocate kmalloc_8 cache");
	kmalloc_caches[2]  = Cache.create("kmalloc_16",   16,    0) catch @panic("Failed to allocate kmalloc_16 cache");
	kmalloc_caches[3]  = Cache.create("kmalloc_32",   32,    0) catch @panic("Failed to allocate kmalloc_32 cache");
	kmalloc_caches[4]  = Cache.create("kmalloc_64",   64,    0) catch @panic("Failed to allocate kmalloc_64 cache");
	kmalloc_caches[5]  = Cache.create("kmalloc_128",  128,   0) catch @panic("Failed to allocate kmalloc_128 cache");
	kmalloc_caches[6]  = Cache.create("kmalloc_256",  256,   1) catch @panic("Failed to allocate kmalloc_256 cache");
	kmalloc_caches[7]  = Cache.create("kmalloc_512",  512,   2) catch @panic("Failed to allocate kmalloc_512 cache");
	kmalloc_caches[8]  = Cache.create("kmalloc_1k",   1024,  3) catch @panic("Failed to allocate kmalloc_1024 cache");
	kmalloc_caches[9]  = Cache.create("kmalloc_2k",   2048,  3) catch @panic("Failed to allocate kmalloc_2048 cache");
	kmalloc_caches[10] = Cache.create("kmalloc_4k",   4096,  3) catch @panic("Failed to allocate kmalloc_4096 cache");
	kmalloc_caches[11] = Cache.create("kmalloc_8k",   8192,  4) catch @panic("Failed to allocate kmalloc_8192 cache");
	kmalloc_caches[12] = Cache.create("kmalloc_16k",  16384, 5) catch @panic("Failed to allocate kmalloc_16384 cache");
	kmalloc_caches[13] = Cache.create("kmalloc_32k",  32768, 5) catch @panic("Failed to allocate kmalloc_32768 cache");
}

pub fn slabinfo() void {
	printk(" "**16, .{});
	printk(" \x1b[36msize\x1b[0m", .{});
	printk("   \x1b[36mo/s\x1b[0m", .{});
	printk("  \x1b[36mact.\x1b[0m", .{});
	printk("   \x1b[36mp/s\x1b[0m", .{});
	printk("  \x1b[36mslabs\x1b[0m", .{});
	printk("  \x1b[36mempty\x1b[0m", .{});
	printk("  \x1b[36mpart.\x1b[0m", .{});
	printk("  \x1b[36mfull\x1b[0m", .{});
	printk("\n", .{});
	var node: ?*Cache = global_cache.next;
	while (node) |n| : (node = n.next) n.debug();
	global_cache.debug();
}

pub fn kmalloc(size: usize) !* align(1) usize {
	return switch(size) {
		0...4 => kmalloc_caches[0].alloc_one(),
		5...8 => kmalloc_caches[1].alloc_one(),
		9...16 => kmalloc_caches[2].alloc_one(),
		17...32 => kmalloc_caches[3].alloc_one(),
		33...64 => kmalloc_caches[4].alloc_one(),
		65...128 => kmalloc_caches[5].alloc_one(),
		129...256 => kmalloc_caches[6].alloc_one(),
		257...512 => kmalloc_caches[7].alloc_one(),
		513...1024 => kmalloc_caches[8].alloc_one(),
		1025...2048 => kmalloc_caches[9].alloc_one(),
		2049...4096 => kmalloc_caches[10].alloc_one(),
		4097...8192 => kmalloc_caches[11].alloc_one(),
		8193...16384 => kmalloc_caches[12].alloc_one(),
		16385...32768 => kmalloc_caches[13].alloc_one(),
		else => Cache.Error.AllocationFailed,
	};
}

pub fn kfree(ptr: *usize) void {
	// printk("kfree: 0x{x}\n", .{@intFromPtr(ptr)});
	global_cache.free(ptr);
}