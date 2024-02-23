const tty = @import("../tty/tty.zig"); // TODO: Remove it
const VirtualPageAllocatorType = @import("../memory.zig").VirtualPageAllocatorType;
const PAGE_SIZE: usize = 4096;
const CACHE_NAME_LEN = 15;

const Bit = enum(u1) {
	Taken,
	Free,
};

const BitMap = struct {
	const Self = @This();

	nb_obj: usize = 0,
	bits: []usize = undefined,

	pub const Error = error{ OutOfBounds };

	pub fn init(self: *Self, addr: [*]usize, nb_obj: usize) void {
		var len = (nb_obj + (8 * @sizeOf(usize)) - 1) / (8 * @sizeOf(usize));

		self.* = BitMap{};
		self.nb_obj = nb_obj;
		self.bits = addr[0..len];
		for (self.bits) |*b| b.* = 0;
	}

	pub fn get_size(self: *Self) usize {
		return self.bits.len * @sizeOf(usize);
	}

	pub fn set(self: *Self, index: usize, value: Bit) !void {
		if (index >= self.nb_obj) return Error.OutOfBounds;

		const i = index / (8 * @sizeOf(usize));
		const mask = @as(usize, 1) << @truncate(index % (8*@sizeOf(usize)));
		switch (value) {
			.Taken => self.bits[i] |= mask,
			.Free  => self.bits[i] &= ~mask,
		}
	}

	pub fn get(self: *Self, index: usize) !Bit {
		if (index >= self.nb_obj) return Error.OutOfBounds;

		const i = index / (8 * @sizeOf(usize));
		const bit = index % (8*@sizeOf(usize));
		return  if ((self.bits[i] >> @truncate(bit)) & 1 == 1) .Taken else .Free;
	}
};

const SlabState = enum {
	Empty,
	Partial,
	Full,
};

const SlabHeader = struct {
	cache: *Cache = undefined,
	next: ?*Slab = null,
	prev: ?*Slab = null,
	in_use: usize = 0,
	next_free: ?u16 = 0,
};

const Slab = struct {
	const Self = @This();

	pub const Error = error{ SlabFull, SlabCorrupted, OutOfBounds, InvalidOrder, InvalidSize };

	header: SlabHeader = SlabHeader{},

	bitmap: BitMap = BitMap{},
	data: []?u16 = undefined,

	pub fn init(self: *Self, cache: *Cache) Error!void {
		self.* = Slab{};

		self.header.cache = cache;

		// Initialize the bitmap just after the slab header
		var hma: [*]usize = @ptrFromInt(@intFromPtr(self) + @sizeOf(Self));
		self.bitmap.init(hma, cache.obj_per_slab);

		// Initialize the objects, just after the bitmap
		var start: usize = @intFromPtr(self) + @sizeOf(Self) + self.bitmap.get_size();
		self.data = @as([*]?u16, @ptrFromInt(start))[0..cache.obj_per_slab * (cache.size_obj / @sizeOf(usize))];

		for (0..cache.obj_per_slab) |i| {
			self.data[i * (cache.size_obj / @sizeOf(usize))] = if (i + 1 < cache.obj_per_slab) @truncate(i + 1) else null;
		}
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
		if (obj_addr < @intFromPtr(&self.data[0]) or obj_addr > @intFromPtr(&self.data[self.data.len - 1])) return; // TODO: Error
		if ((obj_addr - @intFromPtr(&self.data[0])) % self.header.cache.size_obj != 0) return; // TODO: Error

		tty.printk("free object: 0x{x}\n", .{obj_addr});

		const index: u16 = @truncate((obj_addr - @intFromPtr(&self.data[0])) / self.header.cache.size_obj);
		tty.printk("index: {d}\n", .{index});
		if (self.bitmap.get(index) catch .Free == .Free) return; // TODO: Error
		tty.printk("{}\n", .{self.bitmap.get(index) catch .Free});
		self.bitmap.set(index, Bit.Free) catch return; // TODO: Error
		tty.printk("{}\n", .{self.bitmap.get(index) catch .Free});
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
		tty.printk("self: 0x{x}\n", .{@intFromPtr(self)});
		tty.printk("Slab Header:\n", .{});
		inline for (@typeInfo(SlabHeader).Struct.fields) |field|
			tty.printk("  header.{s}: 0x{x} ({d} bytes)\n", .{field.name, @intFromPtr(&@field(self.header, field.name)), @sizeOf(field.type)});

		tty.printk("Bitmap:\n", .{});
		inline for (@typeInfo(BitMap).Struct.fields) |field|
			tty.printk("  bitmap.{s}: 0x{x} ({d} bytes)\n", .{field.name, @intFromPtr(&@field(self.bitmap, field.name)), @sizeOf(field.type)});

		tty.printk("Data:\n", .{});
		tty.printk("  data: 0x{x} ({d} bytes)\n", .{@intFromPtr(&self.data[0]), @sizeOf(@TypeOf(self.data))});
	}
};

const Cache = struct {
	const Self = @This();
	const Error = error{ AllocationFailed };

	next: ?*Cache = null,
	prev: ?*Cache = null,
	slab_full:	?*Slab = null,
	slab_partial: ?*Slab = null,
	slab_empty: ?*Slab = null,
	allocator: *VirtualPageAllocatorType = undefined,
	order: u5 = 0,
	name: [CACHE_NAME_LEN]u8 = undefined,
	nb_slab: usize = 0,
	nb_active_slab: usize = 0,
	obj_per_slab: u16 = 0,
	size_obj: usize = 0,

	pub fn init(
		self: *Self,
		name: []const u8,
		allocator : *VirtualPageAllocatorType,
		obj_size: usize,
		order: u5
	) void {
		self.* = Cache{};
		self.order = order;
		self.allocator = allocator;

		// TODO: Check if the size is valid
		// Align to usize
		self.size_obj = ((obj_size - 1 + @sizeOf(usize)) / @sizeOf(usize)) * @sizeOf(usize);

		// Calculate the available space for the slab ((page_size * 2^order) - sise of slab header)
		const available = (PAGE_SIZE * (@as(usize, 1) << @truncate(order))) - @sizeOf(Self);

		self.obj_per_slab = 0;
		while (true) {
			const bitmap_size = (((self.obj_per_slab + 1) - 1 + (8 * @sizeOf(usize))) / (8 * @sizeOf(usize))) * @sizeOf(usize);
			const total_size = bitmap_size + ((self.obj_per_slab+1) * self.size_obj);
			if (total_size > available) break;
			self.obj_per_slab += 1;
		}
		if (self.obj_per_slab == 0 or self.obj_per_slab >= (1 << 16)) return ;

		const name_len = @min(name.len, CACHE_NAME_LEN);
		@memset(self.name[0..CACHE_NAME_LEN], 0);
		@memcpy(self.name[0..name_len], name[0..name_len]);
		self.debug();
	}

	pub fn grow(self: *Self, nb_slab: usize) Error!void {
		for (0..nb_slab) |_| {
			var obj = self.allocator.alloc_pages(@as(usize, 1) << self.order) catch return Error.AllocationFailed;
			var slab: *Slab = @ptrCast(@alignCast(obj));
			slab.init(self) catch return Error.AllocationFailed;

			for (0..(@as(usize, 1) << self.order)) |i| {
				const page_addr = @as(usize, @intFromPtr(obj)) + (i * PAGE_SIZE);
				tty.printk("init page: 0x{x}\n", .{page_addr});
				var page_descriptor = self.allocator.get_page_frame_descriptor(@ptrFromInt(page_addr));
				page_descriptor.prev = @ptrCast(@alignCast(self));
				page_descriptor.next = @ptrCast(@alignCast(slab));
			}
			if (self.slab_empty) |*lst| {
				slab.header.next = lst.*;
				lst.*.header.prev = slab;
				lst.* = slab;
			} else {
				self.slab_empty = slab;
			}
			self.nb_slab += 1;
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
	}

	pub fn move_slab(self: *Self, slab: *Slab, state: SlabState) void {
		if (state == slab.get_state()) return; // TODO error
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
		const addr = @intFromPtr(ptr) & ~(PAGE_SIZE - 1);
		const page_descriptor = self.allocator.get_page_frame_descriptor(@ptrFromInt(addr));

		tty.printk("cache: 0x{x}\n", .{@intFromPtr(page_descriptor.prev)});
		tty.printk("slab: 0x{x}\n", .{@intFromPtr(page_descriptor.next)});
		const slab: *Slab = @ptrCast(@alignCast(page_descriptor.next));
		slab.free_object(ptr);
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

		tty.printk("\x1b[31m{s}\x1b[0m: ", .{self.name});
		tty.printk("{d} ", .{self.size_obj});
		tty.printk("{d} ", .{self.obj_per_slab});
		tty.printk("{d} ", .{object_in_use});
		tty.printk("{d} ", .{self.nb_slab});
		tty.printk("{d} ", .{nb_slab_empty});
		tty.printk("{d} ", .{nb_slab_partial});
		tty.printk("{d} ", .{nb_slab_full});
		tty.printk("\n", .{});
	}
};

var global_cache: Cache = .{};
var kmalloc_caches: [14]*Cache = undefined;

pub fn create_cache(name: []const u8, obj_size: usize, order: u5) Cache.Error!*Cache {
	var cache: *Cache = @ptrCast(@alignCast(global_cache.alloc_one() catch |e| return e));
	cache.init(name, global_cache.allocator, obj_size, order);
	cache.next = global_cache.next;
	if (global_cache.next) |next| next.prev = cache;
	global_cache.next = cache;
	return cache;
}

pub fn global_cache_init(allocator: *VirtualPageAllocatorType) void {
	tty.printk("global_cache_init\n", .{});
	global_cache.init("cache", allocator, @sizeOf(Cache), 0);
 	kmalloc_caches[0]  = create_cache("kmalloc_4",    4,     0) catch @panic("Failed to allocate kmalloc_4 cache");
	kmalloc_caches[1]  = create_cache("kmalloc_8",    8,     0) catch @panic("Failed to allocate kmalloc_8 cache");
	kmalloc_caches[2]  = create_cache("kmalloc_16",   16,    0) catch @panic("Failed to allocate kmalloc_16 cache");
	kmalloc_caches[3]  = create_cache("kmalloc_32",   32,    0) catch @panic("Failed to allocate kmalloc_32 cache");
	kmalloc_caches[4]  = create_cache("kmalloc_64",   64,    0) catch @panic("Failed to allocate kmalloc_64 cache");
	kmalloc_caches[5]  = create_cache("kmalloc_128",  128,   0) catch @panic("Failed to allocate kmalloc_128 cache");
	kmalloc_caches[6]  = create_cache("kmalloc_256",  256,   1) catch @panic("Failed to allocate kmalloc_256 cache");
	kmalloc_caches[7]  = create_cache("kmalloc_512",  512,   2) catch @panic("Failed to allocate kmalloc_512 cache");
	kmalloc_caches[8]  = create_cache("kmalloc_1k",   1024,  3) catch @panic("Failed to allocate kmalloc_1024 cache");
	kmalloc_caches[9]  = create_cache("kmalloc_2k",   2048,  3) catch @panic("Failed to allocate kmalloc_2048 cache");
	kmalloc_caches[10] = create_cache("kmalloc_4k",   4096,  3) catch @panic("Failed to allocate kmalloc_4096 cache");
	kmalloc_caches[11] = create_cache("kmalloc_8k",   8192,  4) catch @panic("Failed to allocate kmalloc_8192 cache");
	kmalloc_caches[12] = create_cache("kmalloc_16k",  16384, 5) catch @panic("Failed to allocate kmalloc_16384 cache");
	kmalloc_caches[13] = create_cache("kmalloc_32k",  32768, 5) catch @panic("Failed to allocate kmalloc_32768 cache");
}

pub fn slabinfo() void {
	tty.printk("\x1b[36mName\x1b[0m, ", .{});
	tty.printk("\x1b[36mo size\x1b[0m, ", .{});
	tty.printk("\x1b[36mo/slab\x1b[0m, ", .{});
	tty.printk("\x1b[36mo inuse\x1b[0m, ", .{});
	tty.printk("\x1b[36mslabs\x1b[0m, ", .{});
	tty.printk("\x1b[36mse\x1b[0m, ", .{});
	tty.printk("\x1b[36msp\x1b[0m, ", .{});
	tty.printk("\x1b[36msf\x1b[0m, ", .{});
	tty.printk("\n", .{});
	var node: ?*Cache = global_cache.next;
	while (node) |n| : (node = n.next) n.debug();
	global_cache.debug();
}

pub fn kmalloc(size: usize) Cache.Error!* align(1) usize {
	return switch(size) {
		0...4 => kmalloc_caches[0].alloc_one() catch Cache.Error.AllocationFailed,
		5...8 => kmalloc_caches[1].alloc_one() catch Cache.Error.AllocationFailed,
		9...16 => kmalloc_caches[2].alloc_one() catch Cache.Error.AllocationFailed,
		17...32 => kmalloc_caches[3].alloc_one() catch Cache.Error.AllocationFailed,
		33...64 => kmalloc_caches[4].alloc_one() catch Cache.Error.AllocationFailed,
		65...128 => kmalloc_caches[5].alloc_one() catch Cache.Error.AllocationFailed,
		129...256 => kmalloc_caches[6].alloc_one() catch Cache.Error.AllocationFailed,
		257...512 => kmalloc_caches[7].alloc_one() catch Cache.Error.AllocationFailed,
		513...1024 => kmalloc_caches[8].alloc_one() catch Cache.Error.AllocationFailed,
		1025...2048 => kmalloc_caches[9].alloc_one() catch Cache.Error.AllocationFailed,
		2049...4096 => kmalloc_caches[10].alloc_one() catch Cache.Error.AllocationFailed,
		4097...8192 => kmalloc_caches[11].alloc_one() catch Cache.Error.AllocationFailed,
		8193...16384 => kmalloc_caches[12].alloc_one() catch Cache.Error.AllocationFailed,
		16385...32768 => kmalloc_caches[13].alloc_one() catch Cache.Error.AllocationFailed,
		else => Cache.Error.AllocationFailed,
	};
}

pub fn kfree(ptr: *usize) void {
	tty.printk("kfree: 0x{x}\n", .{@intFromPtr(ptr)});
	global_cache.free(ptr);
}