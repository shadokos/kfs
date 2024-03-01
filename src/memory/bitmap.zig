const ft = @import("../ft/ft.zig");

pub const Bit = enum(u1) {
	Taken,
	Free,
};

pub const BitMap = struct {
	const Self = @This();
	const nbits: usize = 8 * @sizeOf(usize);

	nb_obj: usize = 0,
	bits: []usize = undefined,

	pub const Error = error{ OutOfBounds };

	pub fn init(self: *Self, addr: [*]usize, nb_obj: usize) void {
		var len = Self.compute_len(nb_obj);

		self.* = BitMap{};
		self.nb_obj = nb_obj;
		self.bits = addr[0..len];
		for (self.bits) |*b| b.* = 0;
	}

	// return the number of usize needed to store nb_obj bits
	pub fn compute_len(nb_obj: usize) usize {
		return ft.math.divCeil(usize, nb_obj, nbits) catch unreachable;
	}

	// return the number of bytes needed to store nb_obj bits
	pub fn compute_size(nb_obj: usize) usize {
		return Self.compute_len(nb_obj) * @sizeOf(usize);
	}

	// get the size of the current bitmap in bytes
	pub fn get_size(self: *Self) usize {
		return self.bits.len * @sizeOf(usize);
	}

	// set the n-th bit state to value
	pub fn set(self: *Self, n: usize, value: Bit) !void {
		if (n >= self.nb_obj) return Error.OutOfBounds;

		const index = n / nbits;
		const mask = @as(usize, 1) << @truncate(n % nbits);
		switch (value) {
			.Taken => self.bits[index] |= mask,
			.Free  => self.bits[index] &= ~mask,
		}
	}

	// get the n-th bit state
	pub fn get(self: *Self, n: usize) !Bit {
		if (n >= self.nb_obj) return Error.OutOfBounds;

		const index = n / nbits;
		const bit = n % nbits;
		return  if ((self.bits[index] >> @truncate(bit)) & 1 == 1) .Taken else .Free;
	}
};