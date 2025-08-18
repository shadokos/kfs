const printk = @import("../../../tty/tty.zig").printk;
const Cache = @import("cache.zig").Cache;
const BitMap = @import("../../../misc/bitmap.zig").UnsafeBitMap;
const Bit = @import("../../../misc/bitmap.zig").Bit;
const std = @import("std");

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
};

const UnsafeSlotManager = @import("../../../misc/slot_manager.zig").UnsafeSlotManager;

pub const Slab = struct {
    const Self = @This();

    pub const Error = error{ InvalidArgument, SlabFull, SlabCorrupted, DoubleFree };

    header: SlabHeader = SlabHeader{},

    slots: UnsafeSlotManager = undefined,

    pub fn init(cache: *Cache, page: *usize) Slab {
        var new = Slab{ .header = .{ .cache = cache } };

        const end_of_metadata: [*]usize = @ptrFromInt(@intFromPtr(page) + @sizeOf(Slab));
        new.slots = UnsafeSlotManager.init(end_of_metadata, cache.obj_per_slab, cache.size_obj, cache.align_obj);
        return new;
    }

    pub fn alloc_object(self: *Self) Error!*usize {
        _, const obj = self.slots.create(self.header.cache.size_obj) catch |e| return switch (e) {
            UnsafeSlotManager.Error.NoFreeSlot => Error.SlabFull,
            else => Error.SlabCorrupted,
        };

        if (self.header.in_use == 0)
            self.header.cache.unsafe_move_slab(self, .Empty, .Partial);
        if (self.header.in_use + 1 >= self.header.cache.obj_per_slab) {
            self.header.cache.unsafe_move_slab(self, .Partial, .Full);
        }

        self.header.in_use += 1;
        return obj;
    }

    pub fn is_obj_in_slab(self: *Self, obj: *usize) bool {
        const obj_addr = @intFromPtr(obj);

        const start_addr = @intFromPtr(&self.slots.data[0]);
        const end_addr = @intFromPtr(&self.slots.data[self.slots.data.len - 1]);
        if (obj_addr < start_addr or obj_addr > end_addr)
            return false;
        if ((obj_addr - start_addr) % self.header.cache.size_obj != 0)
            return false;
        return true;
    }

    pub fn free_object(self: *Self, obj: *usize) (Error || BitMap.Error)!void {
        if (!self.is_obj_in_slab(obj))
            return Error.InvalidArgument;

        self.slots.destroy(obj, self.header.cache.size_obj) catch |e| return switch (e) {
            UnsafeSlotManager.Error.NotAllocated => Error.DoubleFree,
            else => Error.SlabCorrupted,
        };

        if (self.header.in_use == self.header.cache.obj_per_slab)
            self.header.cache.unsafe_move_slab(self, .Full, .Partial);
        if (self.header.in_use == 1)
            self.header.cache.unsafe_move_slab(self, .Partial, .Empty);

        self.header.in_use -= 1;
    }

    pub fn get_state(self: *Self) SlabState {
        if (self.slots.next_free == null) return .Full;
        if (self.header.in_use == 0) return .Empty;
        return .Partial;
    }

    // TODO: Remove this method, for debugging purpose only...
    pub fn debug(self: *Self) void {
        printk("self: 0x{x}\n", .{@intFromPtr(self)});
        printk("Slab Header:\n", .{});
        inline for (@typeInfo(SlabHeader).Struct.fields) |field|
            printk("  header.{s}: 0x{x} ({d} bytes)\n", .{
                field.name,
                @intFromPtr(&@field(self.header, field.name)),
                @sizeOf(field.type),
            });

        printk("Bitmap:\n", .{});
        inline for (@typeInfo(BitMap).Struct.fields) |field|
            printk("  bitmap.{s}: 0x{x} ({d} bytes)\n", .{
                field.name,
                @intFromPtr(&@field(self.slots.bitmap, field.name)),
                @sizeOf(field.type),
            });

        printk("Data:\n", .{});
        printk("  data: 0x{x} ({d} bytes)\n", .{
            @intFromPtr(&self.slots.data[0]),
            @sizeOf(@TypeOf(self.slots.data)),
        });

        printk("Values:\n", .{});
        if (self.slots.next_free) |next_free| printk("  next_free: {d}\n", .{
            next_free,
        }) else printk("  next_free: null\n", .{});
        printk("  cache: 0x{x}\n", .{@intFromPtr(self.header.cache)});
        if (self.header.next) |next| printk("  next: 0x{x}\n", .{
            @intFromPtr(next),
        }) else printk("  next: null\n", .{});
        if (self.header.prev) |prev| printk("  prev: 0x{x}\n", .{
            @intFromPtr(prev),
        }) else printk("  prev: null\n", .{});
        printk("  in_use: {d}\n", .{self.header.in_use});
        printk("  state: {d}\n", .{self.get_state()});
        printk("\n", .{});
    }
};
