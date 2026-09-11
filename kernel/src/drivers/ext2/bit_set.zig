const std = @import("std");

buffer: []StoreType,

pub const StoreType = u8;
const BitIndex = std.math.Log2Int(StoreType);

const Self = @This();

pub fn init(buffer: []StoreType) Self {
    return .{
        .buffer = buffer,
    };
}

fn elementIndex(index: u32) usize {
    return index >> std.math.log2(@bitSizeOf(StoreType));
}

fn bitIndex(index: u32) BitIndex {
    return @truncate(index);
}

pub fn set(self: Self, index: usize) void {
    self.buffer[elementIndex(index)] |= @as(StoreType, 1) << bitIndex(index);
}

pub fn unset(self: Self, index: usize) void {
    self.buffer[elementIndex(index)] &= ~(@as(StoreType, 1) << bitIndex(index));
}

pub fn is_set(self: Self, index: usize) bool {
    return ((self.buffer[elementIndex(index)] >> bitIndex(index)) & 1) == 1;
}

pub fn toggle_first_unset(self: Self) ?usize {
    for (self.buffer, 0..) |*e, i| {
        if (~e.* != 0) {
            inline for (0..@bitSizeOf(StoreType)) |bit| {
                if ((e.* >> bit) & 1 == 0) {
                    e.* |= (1 << bit);
                    return (i << std.math.log2(@bitSizeOf(StoreType))) | @as(std.math.Log2Int(BitIndex), @truncate(bit));
                }
            }
        }
    }
    return null;
}
