const ft = @import("ft.zig");
const assert = ft.debug.assert;
const Allocator = ft.mem.Allocator;

pub fn ArrayList(comptime T: type) type {
    return ArrayListAligned(T, 1); // todo align
}

pub fn ArrayListAligned(comptime T: type, comptime alignment: ?u29) type {
    return struct {
        allocator: Allocator,
        slice: Slice = &[_]T{},
        capacity: usize = 0,

        // https://ziglang.org/documentation/master/std/#std.array_list.ArrayListAligned.SentinelSlice
        pub fn SentinelSlice(comptime s: T) type {
            return if (alignment) |a| ([:s]align(a) T) else [:s]T;
        }

        // https://ziglang.org/documentation/master/std/#std.array_list.ArrayListAligned.Slice
        pub const Slice = if (alignment) |a| ([]align(a) T) else []T;

        // https://ziglang.org/documentation/master/std/#std.array_list.ArrayListAligned.Writer
        pub const Writer = if (T != u8)
            @compileError("The Writer interface is only defined for ArrayList(u8) " ++
                "but the given type is ArrayList(" ++ @typeName(T) ++ ")")
        else
            ft.io.Writer(*Self, Allocator.Error, appendWrite);

        const Self = @This();

        pub fn init(allocator: Allocator) Self {
            return Self{
                .allocator = allocator,
            };
        }

        pub fn initCapacity(allocator: Allocator, num: usize) Allocator.Error!Self {
            const self = Self{
                .allocator = allocator,
            };
            self.ensureTotalCapacity(num);
            return self;
        }

        pub fn fromOwnedSlice(allocator: Allocator, slice: Slice) Self {
            return Self{ .allocator = allocator, .slice = slice, .capacity = slice.len };
        }

        pub fn fromOwnedSliceSentinel(allocator: Allocator, comptime sentinel: T, slice: [:sentinel]T) Self {
            return Self{ .allocator = allocator, .slice = slice, .capacity = slice.len + 1 };
        }

        pub fn addManyAsArray(self: *Self, comptime n: usize) Allocator.Error!*[n]T {
            return @ptrCast(&(try self.addManyAsSlice(n))[0]);
        }

        pub fn addManyAsArrayAssumeCapacity(self: *Self, comptime n: usize) *[n]T {
            return @ptrCast(&self.addManyAsSlice(n)[0]);
        }

        pub fn addManyAsSlice(self: *Self, n: usize) Allocator.Error![]T {
            return self.addManyAt(self.slice.len, n);
        }

        pub fn addManyAsSliceAssumeCapacity(self: *Self, n: usize) []T {
            return self.addManyAtAssumeCapacity(self.slice.len, n);
        }

        pub fn addManyAt(self: *Self, index: usize, count: usize) Allocator.Error![]T {
            if (self.capacity < self.slice.len + count) {
                try self.ensureTotalCapacity(self.capacity + count);
            }

            return self.addManyAtAssumeCapacity(index, count);
        }

        pub fn addManyAtAssumeCapacity(self: *Self, index: usize, count: usize) []T {
            assert(self.capacity >= self.slice.len + count);

            ft.mem.copyBackwards(
                T,
                self.slice.ptr[index + count .. self.slice.len + count],
                self.slice.ptr[index..self.slice.len],
            );
            const ret: []T = self.slice.ptr[index .. index + count];
            self.slice.len += count;
            return ret;
        }

        pub fn addOne(self: *Self) Allocator.Error!*T {
            return &(try self.addManyAsSlice(1))[0];
        }

        pub fn addOneAssumeCapacity(self: *Self) *T {
            return &self.addManyAsSlice(1)[0];
        }

        pub fn allocatedSlice(self: Self) Slice {
            return self.slice[0..self.capacity];
        }

        pub fn append(self: *Self, item: T) Allocator.Error!void {
            (try self.addOne()).* = item;
        }

        pub fn appendAssumeCapacity(self: *Self, item: T) void {
            self.addOneAssumeCapacity().* = item;
        }

        pub inline fn appendNTimes(self: *Self, value: T, n: usize) Allocator.Error!void {
            var array = try self.addManyAsArray(n);
            @memset(array, value);
        }

        pub inline fn appendNTimesAssumeCapacity(self: *Self, value: T, n: usize) void {
            var array = self.addManyAsArrayAssumeCapacity(n);
            @memset(array, value);
        }

        pub fn appendSlice(self: *Self, items: []const T) Allocator.Error!void {
            @memcpy(try self.addManyAsSlice(items.len), items);
        }

        fn appendWrite(self: *Self, m: []const u8) Allocator.Error!usize {
            try self.appendSlice(m);
            return m.len;
        }

        pub fn appendSliceAssumeCapacity(self: *Self, items: []const T) void {
            @memcpy(self.addManyAsSliceAssumeCapacity(items.len), items);
        }

        pub fn appendUnalignedSlice(self: *Self, items: []align(1) const T) Allocator.Error!void {
            @memcpy(try self.addManyAsSlice(items.len), items);
        }

        pub fn appendUnalignedSliceAssumeCapacity(self: *Self, items: []align(1) const T) void {
            @memcpy(self.addManyAsSliceAssumeCapacity(items.len), items);
        }

        pub fn clearAndFree(self: *Self) void {
            if (self.capacity != 0) {
                self.allocator.free(self.slice);
                self.slice = &[_]T{};
                self.capacity = 0;
            }
        }

        pub fn clearRetainingCapacity(self: *Self) void {
            self.slice.len = 0;
        }

        pub fn clone(self: Self) Allocator.Error!Self {
            const ret = Self{
                .allocator = self.allocator,
                .slice = try self.allocator.alignedAlloc(T, alignment, self.capacity),
                .capacity = self.capacity,
            };
            ret.slice.len = self.slice.len;
            @memcpy(ret.slice, self.slice);
            return ret;
        }

        pub fn deinit(self: Self) void {
            if (self.capacity != 0) {
                self.allocator.free(self.slice);
            }
        }

        pub fn ensureTotalCapacity(self: *Self, new_capacity: usize) Allocator.Error!void {
            if (self.capacity < new_capacity) {
                var actual_new_capacity = self.capacity;
                if (actual_new_capacity == 0)
                    actual_new_capacity = 16;
                while (actual_new_capacity < new_capacity) {
                    actual_new_capacity *|= 2;
                }
                try self.ensureTotalCapacityPrecise(actual_new_capacity);
            }
        }

        pub fn ensureTotalCapacityPrecise(self: *Self, new_capacity: usize) Allocator.Error!void {
            if (self.capacity < new_capacity) {
                var new_data = try self.allocator.alignedAlloc(T, alignment, new_capacity);
                @memcpy(new_data[0..self.slice.len], self.slice);
                if (self.slice.len != 0) {
                    self.allocator.free(self.slice);
                }
                self.slice.ptr = new_data.ptr;
                self.capacity = new_capacity;
            }
        }

        pub fn ensureUnusedCapacity(self: *Self, additional_count: usize) Allocator.Error!void {
            self.ensureTotalCapacity(self.slice.len + additional_count);
        }

        pub fn expandToCapacity(self: *Self) void {
            self.slice.len = self.capacity;
        }

        pub fn getLast(self: Self) T {
            assert(self.slice.len != 0);
            return self.getLastOrNull().?;
        }

        pub fn getLastOrNull(self: Self) ?T {
            return if (self.slice.len != 0) self.slice[self.slice.len - 1] else null;
        }

        pub fn insert(self: *Self, i: usize, item: T) Allocator.Error!void {
            (try self.addManyAt(i, 1)).* = item;
        }

        pub fn insertAssumeCapacity(self: *Self, i: usize, item: T) void {
            self.addManyAtAssumeCapacity(i, 1).* = item;
        }

        pub fn insertSlice(
            self: *Self,
            index: usize,
            items: []const T,
        ) Allocator.Error!void {
            @memcpy(try self.addManyAt(index, items.len), items);
        }

        // pub fn moveToUnmanaged(self: *Self) ArrayListAlignedUnmanaged(T, alignment)

        pub fn orderedRemove(self: *Self, i: usize) T {
            assert(i < self.slice.len);
            const ret = self.slice[i];
            for (i..self.slice.len - 1) |j| {
                self.slice[j] = self.slice[j + 1];
            }
            self.slice.len -= 1;
            return ret;
        }

        pub fn pop(self: *Self) T {
            assert(self.slice.len != 0);
            return self.popOrNull().?;
        }

        pub fn popOrNull(self: *Self) ?T {
            if (self.slice.len != 0) {
                self.slice.len -= 1;
                return self.slice[self.slice.len];
            } else {
                return null;
            }
        }

        pub fn replaceRange(self: *Self, start: usize, len: usize, new_items: []const T) Allocator.Error!void {
            if (new_items.len > len and self.slice.len + (new_items.len - len) > self.capacity) {
                try self.ensureTotalCapacity(self.capacity + (new_items.len - len));
            }
            self.replaceRangeAssumeCapacity(start, len, new_items);
        }

        pub fn replaceRangeAssumeCapacity(self: *Self, start: usize, len: usize, new_items: []const T) void {
            assert(start +| len <= self.slice.len);
            if (new_items.len > len) {
                assert(self.slice.len + (new_items.len - len) <= self.capacity);
                _ = self.addManyAtAssumeCapacity(start + len, new_items.len - len);
            } else if (new_items.len < len) {
                const offset = len - new_items.len;
                ft.mem.copyForwards(
                    T,
                    self.slice[start + len - offset .. self.slice.len - offset],
                    self.slice[start + len .. self.slice.len],
                );
                self.slice.len -= offset;
            }
            @memcpy(self.slice[start .. start + new_items.len], new_items);
        }

        pub fn resize(self: *Self, new_len: usize) Allocator.Error!void {
            try self.ensureTotalCapacityPrecise(new_len);
            self.expandToCapacity();
        }

        pub fn shrinkAndFree(self: *Self, new_len: usize) void { // todo: try resize
            assert(new_len <= self.slice.len);
            var new_slice = self.allocator.alignedAlloc(T, alignment, new_len) catch {
                return self.shrinkRetainingCapacity(new_len);
            };
            @memcpy(new_slice[0..new_len], self.slice[0..new_len]);
            self.allocator.free(self.slice);
            self.slice = new_slice;
            self.capacity = new_len;
        }

        pub fn shrinkRetainingCapacity(self: *Self, new_len: usize) void {
            assert(new_len <= self.slice.len);
            self.slice.len = new_len;
        }

        pub fn swapRemove(self: *Self, i: usize) T {
            assert(i < self.slice.len);
            const ret = self.slice[i];
            self.slice[i] = self.getLast();
            self.slice.len -= 1;
            return ret;
        }

        pub fn toOwnedSlice(self: *Self) Allocator.Error!Slice {
            const ret = self.slice;
            self.slice = &[_]T{};
            self.capacity = 0;
            return ret;
        }

        pub fn toOwnedSliceSentinel(self: *Self, comptime sentinel: T) Allocator.Error!SentinelSlice(sentinel) {
            const ret = self.slice[0 .. self.slice.len - 1];
            self.slice = &[_]T{};
            self.capacity = 0;
            return ret;
        }

        pub fn unusedCapacitySlice(self: Self) Slice {
            return self.slice.ptr[self.slice.len..self.capacity];
        }

        pub fn writer(self: *Self) Writer {
            return Writer{ .context = self };
        }
    };
}
