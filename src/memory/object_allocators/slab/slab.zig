const printk = @import("../../../tty/tty.zig").printk;
const Cache = @import("cache.zig").Cache;
const BitMap = @import("../../../misc/bitmap.zig").BitMap;
const Bit = @import("../../../misc/bitmap.zig").Bit;

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

    pub const Error = error{ InvalidArgument, SlabFull, SlabCorrupted, DoubleFree };

    header: SlabHeader = SlabHeader{},

    bitmap: BitMap = BitMap{},
    data: []?u16 = undefined,

    pub fn init(cache: *Cache, page: *usize) Slab {
        var new = Slab{ .header = .{ .cache = cache } };

        const mem: [*]usize = @ptrFromInt(@intFromPtr(page) + @sizeOf(Slab));
        new.bitmap = BitMap.init(mem, cache.obj_per_slab);

        const start = @intFromPtr(page) + @sizeOf(Slab) + new.bitmap.get_size();
        new.data = @as([*]?u16, @ptrFromInt(start))[0 .. cache.obj_per_slab * (cache.size_obj / @sizeOf(usize))];

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

    pub fn is_obj_in_slab(self: *Self, obj: *usize) bool {
        const obj_addr = @intFromPtr(obj);

        if (obj_addr < @intFromPtr(&self.data[0]) or obj_addr > @intFromPtr(&self.data[self.data.len - 1]))
            return false;
        if ((obj_addr - @intFromPtr(&self.data[0])) % self.header.cache.size_obj != 0)
            return false;
        return true;
    }

    pub fn free_object(self: *Self, obj: *usize) (Error || BitMap.Error)!void {
        const obj_addr = @intFromPtr(obj);

        if (!self.is_obj_in_slab(obj))
            return Error.InvalidArgument;

        const index: u16 = @truncate((obj_addr - @intFromPtr(&self.data[0])) / self.header.cache.size_obj);
        if (self.bitmap.get(index) catch unreachable == .Free) return Error.DoubleFree;
        self.bitmap.set(index, Bit.Free) catch unreachable;
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
                @intFromPtr(&@field(self.bitmap, field.name)),
                @sizeOf(field.type),
            });

        printk("Data:\n", .{});
        printk("  data: 0x{x} ({d} bytes)\n", .{ @intFromPtr(&self.data[0]), @sizeOf(@TypeOf(self.data)) });

        printk("Values:\n", .{});
        if (self.header.next_free) |next_free| printk("  next_free: {d}\n", .{
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
