const ft = @import("../ft.zig");

// most of the code in this file is a translation of the code present in https://prng.di.unimi.it/xoroshiro128plus.c

s: [2]u64,

const Xoroshiro128 = @This();

pub fn fill(self: *Xoroshiro128, buf: []u8) void {
	var i : u32 = 0;
	while (i < buf.len) {
		const n : u64 = self.next();
		for (buf[i..@min(i+8, buf.len - i)], 0..) |*c, j| {
			c.* = @intCast((n >> @as(u6, @intCast(j * 8))) & 0xff);
		}
		i += 8;
	}
}

pub fn init(init_s: u64) Xoroshiro128 {
	var ret : Xoroshiro128 = undefined;
	ret.seed(init_s);
	return ret;
}

pub fn jump(self: *Xoroshiro128) void {
	const JUMP = []u64{ 0xdf900294d8f554a5, 0x170865df4b3201fc };

	var s0 : u64 = 0;
	var s1 : u64 = 0;
	for(JUMP) |j| {
		for(0..64) |b| {
			if (j & @as(u64, 1) << @as(u6, b)) {
				s0 ^= self.s[0];
				s1 ^= self.s[1];
			}
			self.next();
		}
	}

	self.s[0] = s0;
	self.s[1] = s1;
}

fn rotl(x : u64, k : u6) u64 {
	return (x << k) | (x >> (-%k));
}

pub fn next(self: *Xoroshiro128) u64 {

	const s0 = self.s[0];
	var s1 : u64 = self.s[1];

	const result : u64 = s0 +% s1;

	s1 ^= s0;
	self.s[0] = rotl(s0, 24) ^ s1 ^ (s1 << 16);
	self.s[1] = rotl(s1, 37);

	return result;
}

pub fn random(self: *Xoroshiro128) ft.Random {
	return ft.Random.init(self, fill);
}

pub fn seed(self: *Xoroshiro128, init_s: u64) void {
	self.s[0] = init_s;
	self.s[1] = init_s;
}