const ft = @import("../ft/ft.zig");
const paging = @import("paging.zig");
const printk = @import("../tty/tty.zig").printk;

pub fn Fuzzer(comptime AllocatorType : type) type {
	return struct {
		allocator : *AllocatorType,
		allocs : [1000] Alloc = undefined,
		size : usize = 0,
		n_alloc : usize = 0,
		n_free : usize = 0,
		rand : ft.Random = undefined,

		var xoro = ft.Random.Xoroshiro128.init(42);
		const Alloc = []u8;

		const Self = @This();

		pub fn init(_allocator : *AllocatorType) Self {
			return Self{.allocator = _allocator, .rand = xoro.random()};
		}

		fn checksum(n : usize) u8 {
			return @truncate(((n >> 0) & 0xff) ^ ((n >> 8) & 0xff) ^ ((n >> 16) & 0xff) ^ ((n >> 24) & 0xff));
		}

		pub fn fuzz(self : *Self, iterations : usize) !void {
			for (0..iterations) |_| {
				if (self.rand.boolean()) {
					const size = self.rand.intRangeAtMost(usize, 1, 1000);
					const ptr = try self.allocator.alloc(u8, size);
					self.n_alloc +|= 1;
					@memset(ptr, @as(u8, checksum(@intFromPtr(ptr.ptr))));
					self.add_chunk(ptr);
					printk("\x1b[31malloc({d}) = 0x{x:0>8}\x1b[0m\n", .{size, @intFromPtr(ptr.ptr)});
				} else if (self.size != 0) {
					const chunk = self.rand.intRangeLessThan(usize, 0, self.size);
					const ptr = self.allocs[chunk].ptr;
					printk("\x1b[31mfree(0x{x:0>8})\x1b[0m\n", .{@intFromPtr(ptr)});
					const sum = checksum(@intFromPtr(ptr));
					for (self.allocs[chunk], 0..) |c, i| {
						if (c != sum) {
							printk("invalid checksum, expected {x}, got {x}{x}{x}{x} at {d}\n", .{sum, c, self.allocs[chunk][i+1], self.allocs[chunk][i+2], self.allocs[chunk][i+3], i});
							return error.FuzzingFailure;
						}
					}
					self.remove_chunk(chunk);
					self.n_free +|= 1;
					self.allocator.free(@as(*usize, @alignCast(@ptrCast(ptr))));
				}
			}
		}

		fn add_chunk(self : *Self, alloc : Alloc) void {
			if (self.size < self.allocs.len) {
				self.allocs[self.size] = alloc;
				self.size += 1;
			}
		}

		fn remove_chunk(self : *Self, n : usize) void {
			self.allocs[n] = self.allocs[self.size - 1];
			self.size -= 1;
		}

		pub fn status(self : *Self) void {
			printk("{d} allocations\n", .{self.n_alloc});
			printk("{d} free\n", .{self.n_free});
			printk("{d} active\n", .{self.size});
		}
	};
}