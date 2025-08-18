const std = @import("std");

pub fn SlotManager(comptime T: type, comptime nb_slots: u32) type {
    return struct {
        const Self = @This();
        const BitMap = @import("bitmap.zig").BitMap(nb_slots);

        const index_t: type = switch (nb_slots) {
            0...std.math.maxInt(u8) => u8,
            std.math.maxInt(u8) + 1...std.math.maxInt(u16) => u16,
            std.math.maxInt(u16) + 1...std.math.maxInt(u32) => u32,
        };

        const Node = union {
            data: T,
            free_next: ?index_t,
        };

        bitmap: BitMap = .{},
        slots: [nb_slots]Node = undefined,
        next_free: ?index_t = 0,

        pub const Error = error{ NoFreeSlot, NotAllocated };

        pub fn init() Self {
            var slots: [nb_slots]Node = undefined;
            for (0..nb_slots) |i| {
                slots[i] = .{ .free_next = if (i + 1 < nb_slots) @truncate(i + 1) else null };
            }
            return Self{
                .slots = slots,
            };
        }

        pub fn create(self: *Self, data: T) !struct { index_t, *T } {
            const index = self.next_free orelse return Self.Error.NoFreeSlot;

            try self.bitmap.set(index, .Taken);

            const slot = &self.slots[index];
            self.next_free = slot.free_next;
            slot.* = .{ .data = data };
            return .{ index, &slot.data };
        }

        pub fn destroy(self: *Self, index: index_t) !void {
            if (index >= nb_slots) return Self.Error.NotAllocated;
            if (try self.bitmap.get(index) != .Taken) return Self.Error.NotAllocated;

            const slot = &self.slots[index];

            try self.bitmap.set(index, .Free);

            slot.* = .{ .free_next = self.next_free };
            self.next_free = index;
        }
    };
}

pub const UnsafeSlotManager = struct {
    const Self = @This();
    const BitMap = @import("bitmap.zig").UnsafeBitMap;

    next_free: ?u16 = 0,
    bitmap: BitMap = BitMap{},
    data: []?u16 = undefined,

    pub const Error = error{ NoFreeSlot, NotAllocated, Corrupted };

    pub fn init(end_of_meta: [*]usize, nb_slots: usize, slot_size: u24, alignment: usize) Self {
        var new = Self{
            .bitmap = BitMap.init(end_of_meta, nb_slots),
        };
        const start = std.mem.alignForward(
            usize,
            @intFromPtr(end_of_meta) + new.bitmap.get_size(),
            alignment,
        );
        new.data = @as([*]?u16, @ptrFromInt(start))[0 .. nb_slots * (slot_size / @sizeOf(usize))];
        for (0..nb_slots) |i| {
            new.data[i * (slot_size / @sizeOf(usize))] =
                if (i + 1 < nb_slots) @truncate(i + 1) else null;
        }
        return new;
    }

    // As we don't store the size of the slo
    pub fn create(self: *Self, slot_size: u24) !struct { u16, *usize } {
        const next = self.next_free orelse return Self.Error.NoFreeSlot;

        self.bitmap.set(next, .Taken) catch return Self.Error.Corrupted;
        const index = next * (slot_size / @sizeOf(usize));
        self.next_free = self.data[index];

        return .{ @truncate(index), @ptrCast(@alignCast(&self.data[index])) };
    }

    pub fn destroy(self: *Self, obj: *usize, slot_size: u24) !void {
        const obj_addr = @intFromPtr(obj);
        const index: u16 = @truncate((obj_addr - @intFromPtr(&self.data[0])) / slot_size);
        if (self.bitmap.get(index) catch unreachable == .Free) return Self.Error.NotAllocated;
        self.bitmap.set(index, .Free) catch return Self.Error.Corrupted;

        self.data[index * (slot_size / @sizeOf(usize))] = self.next_free;
        self.next_free = index;
    }
};
