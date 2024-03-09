const ft = @import("../ft/ft.zig");
const paging = @import("paging.zig");
const printk = @import("../tty/tty.zig").printk;

pub fn Fuzzer(comptime bag_size : comptime_int) type {
	return struct {
		/// instance of the tested allocator
		allocator : ft.mem.Allocator,
		/// bag of allocated chunks
		chunks : [bag_size] Alloc = undefined,
		/// current size of the bag
		size : usize = 0,
		/// number of allocations made (for stats)
		n_alloc : usize = 0,
		/// number of free made (for stats)
		n_free : usize = 0,
		/// random object used for rng
		rand : ft.Random = undefined,
		/// the strategy used for this fuzzing
		strategy : Strategy,

		/// global instance of the xoroshiro algorithm
		var xoro = ft.Random.Xoroshiro128.init(42);

		/// type of an allocation
		const Alloc = []u8;

		/// type of a strategy
		const Strategy = *const fn (*Self, Action) Action;

		/// default strategy
		const default_strategy : Strategy = &uniform;

		/// available actions at each iteration
		const Action = enum {
			Allocate,
			Free,
		};

		const Self = @This();

		/// init a fuzzer object
		pub fn init(_allocator : ft.mem.Allocator, _strategy : ?Strategy) Self {
			return Self{.allocator = _allocator, .rand = xoro.random(), .strategy = _strategy orelse default_strategy};
		}

		/// deinit a fuzzer object
		pub fn deinit(self : *Self) void {
			for (self.chunks[0..self.size]) |c| {
				self.allocator.free(c);
			}
		}

		/// compute the checksum of a pointer
		fn checksum(n : usize) u8 {
			return @truncate(((n >> 0) & 0xff) ^ ((n >> 8) & 0xff) ^ ((n >> 16) & 0xff) ^ ((n >> 24) & 0xff));
		}

		/// main function, iterations is the number of actions that will be made, max_size is the maximum size of an allocation
		pub fn fuzz(self : *Self, iterations : usize, max_size : usize) !void {
			var action : Action = .Allocate;
			for (0..iterations) |_| {
				action = self.strategy(self, action);
				switch (action) {
					.Allocate => {
						const size = self.rand.intRangeAtMost(usize, 1, max_size);
						const ptr = self.allocator.alloc(u8, size) catch |e| {
							printk("\x1b[31mUnable to allocate: {s}\x1b[0m\n", .{@errorName(e)});
							return error.FuzzingFailure;
						};
						self.n_alloc +|= 1;
						@memset(ptr, @as(u8, checksum(@intFromPtr(ptr.ptr))));
						self.add_chunk(ptr);
						printk("\x1b[37malloc(\x1b[34m{d: <5}\x1b[37m)\x1b[31m => \x1b[34m0x{x:0>8}\x1b[0m checksum: \x1b[35m{x:0>2}\x1b[0m\n", .{size, @intFromPtr(ptr.ptr), checksum(@intFromPtr(ptr.ptr))});
					},
					.Free => if (self.size != 0) {
						const chunk = self.rand.intRangeLessThan(usize, 0, self.size);
						const slice = self.chunks[chunk];
						const ptr = slice.ptr;
						printk("\x1b[37mfree(\x1b[34m0x{x:0>8}\x1b[37m)\x1b[0m\n", .{@intFromPtr(ptr)});
						const sum = checksum(@intFromPtr(ptr));
						for (self.chunks[chunk], 0..) |c, i| {
							if (c != sum) {
								printk("\x1b[31mInvalid checksum, expected \x1b[35m{x:0>2}\x1b[31m, got [\x1b[35m{x:0>2}\x1b[31m]\x1b[31m at \x1b[34m{d}\x1b[0m\n", .{sum, c, i});
								return error.FuzzingFailure;
							}
						}
						self.remove_chunk(chunk);
						self.n_free +|= 1;
						self.allocator.free(slice);
					}
				}
			}
			printk("\n\x1b[32mSuccess!\x1b[0m\n", .{});
			self.status();
		}

		/// streaks strategy (alternate between many allocation and many free)
		pub fn streaks(self : *Self, previous_choice : Action) Action {
			return if (self.rand.intRangeAtMost(usize, 0, 100) > 5) previous_choice else switch (previous_choice) {
				.Free => .Allocate,
				.Allocate => .Free,
			};
		}

		/// uniform strategy (one chance out of two for each action)
		pub fn uniform(self : *Self, previous_choice : Action) Action {
			_ = previous_choice;
			return if (self.rand.boolean()) .Allocate else .Free;
		}

		/// converging strategy (the size of the bag converge towards half of its capacity)
		pub fn converging(self : *Self, previous_choice : Action) Action {
			_ = previous_choice;
			return if (self.rand.intRangeAtMost(usize, 0, bag_size) > self.size) .Allocate else .Free;
		}

		/// add a chunk to the bag
		fn add_chunk(self : *Self, alloc : Alloc) void {
			if (self.size < self.chunks.len) {
				self.chunks[self.size] = alloc;
				self.size += 1;
			}
		}

		/// remove a chunk from the bag
		fn remove_chunk(self : *Self, n : usize) void {
			self.chunks[n] = self.chunks[self.size - 1];
			self.size -= 1;
		}

		/// print the current status of the fuzzer
		pub fn status(self : *Self) void {
			printk("Status:\n", .{self.n_alloc});
			printk("\x1b[31m{d: <6}\x1b[0m allocations\n", .{self.n_alloc});
			printk("\x1b[31m{d: <6}\x1b[0m free\n", .{self.n_free});
			printk("\x1b[31m{d: <6}\x1b[0m active\n", .{self.size});
		}
	};
}