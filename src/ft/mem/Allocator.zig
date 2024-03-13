const ft = @import("../ft.zig");

ptr: *anyopaque,
vtable: *const VTable,

pub const VTable = struct {
    alloc: *const fn (ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8,
    resize: *const fn (ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool,
    free: *const fn (ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void,
};

const Allocator = @This();

pub const Error = error{OutOfMemory};

// fn alignedAlloc(self: Allocator, comptime T: type, comptime alignment: ?u29, n: usize) Error![]align(alignment orelse @alignOf(T)) T

pub fn alloc(self: Allocator, comptime T: type, n: usize) Error![]T {
    return @as([*]T, @ptrCast(self.rawAlloc(n * @sizeOf(T), ft.math.log2(@alignOf(T)), @returnAddress()) orelse return Error.OutOfMemory))[0..n];
}

// inline fn allocAdvancedWithRetAddr(self: Allocator, comptime T: type, comptime alignment: ?u29, n: usize, return_address: usize) Error![]align(alignment orelse @alignOf(T)) T

// fn allocSentinel(self: Allocator, comptime Elem: type, n: usize, comptime sentinel: Elem) Error![:sentinel]Elem

// fn allocWithOptions(self: Allocator, comptime Elem: type, n: usize, comptime optional_alignment: ?u29, comptime optional_sentinel: ?Elem) Error!AllocWithOptionsPayload(Elem, optional_alignment, optional_sentinel)

// fn allocWithOptionsRetAddr(self: Allocator, comptime Elem: type, n: usize, comptime optional_alignment: ?u29, comptime optional_sentinel: ?Elem, return_address: usize) Error!AllocWithOptionsPayload(Elem, optional_alignment, optional_sentinel)

fn create(self: Allocator, comptime T: type) Error!*T {
    return &(try self.alloc(T, 1))[0];
}

fn destroy(self: Allocator, ptr: anytype) void {
    const T = @typeInfo(@TypeOf(ptr)).Pointer.child;
    return self.free(@as([*]T, @ptrCast(@alignCast(ptr)))[0..1]);
}

fn dupe(allocator: Allocator, comptime T: type, m: []const T) Error![]T {
    var ret = try allocator.alloc(T, m.len);
    @memcpy(ret[0..], m[0..]);
    return ret;
}

// fn dupeZ(allocator: Allocator, comptime T: type, m: []const T) Error![:0]T

pub fn free(self: Allocator, memory: anytype) void {
    const T = @typeInfo(@TypeOf(memory)).Pointer.child;
    self.rawFree(@as([*]u8, @ptrCast(@alignCast(memory.ptr)))[0 .. memory.len * @sizeOf(T)], ft.math.log2(@alignOf(T)), @returnAddress());
}

// fn noFree(self: *anyopaque, buf: []u8, log2_buf_align: u8, ret_addr: usize) void

// fn noResize(self: *anyopaque, buf: []u8, log2_buf_align: u8, new_len: usize, ret_addr: usize) bool

inline fn rawAlloc(self: Allocator, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
    return self.vtable.alloc(self.ptr, len, ptr_align, ret_addr);
}

inline fn rawFree(self: Allocator, buf: []u8, log2_buf_align: u8, ret_addr: usize) void {
    return self.vtable.free(self.ptr, buf, log2_buf_align, ret_addr);
}

inline fn rawResize(self: Allocator, buf: []u8, log2_buf_align: u8, new_len: usize, ret_addr: usize) bool {
    return self.vtable.resize(self.ptr, buf, log2_buf_align, new_len, ret_addr);
}

fn realloc(self: Allocator, old_mem: anytype, new_n: usize) t: {
    const Slice = @typeInfo(@TypeOf(old_mem)).Pointer;
    break :t Error![]align(Slice.alignment) Slice.child;
} {
    const Slice = @typeInfo(@TypeOf(old_mem)).Pointer;

    if (self.resize(old_mem, new_n)) {
        return old_mem;
    } else {
        var ret = try self.alloc(Slice.child, new_n);
        @memcpy(ret[0..old_mem.len], old_mem[0..]);
        return ret;
    }
}

// fn reallocAdvanced(self: Allocator, old_mem: anytype, new_n: usize, return_address: usize) t: { const Slice = @typeInfo(@TypeOf(old_mem)).Pointer; break :t Error![]align(Slice.alignment) Slice.child; }

fn resize(self: Allocator, old_mem: anytype, new_n: usize) bool {
    const T = @typeInfo(@TypeOf(old_mem)).Pointer.child;
    return self.rawResize(@as([*]u8, @ptrCast(@alignCast(old_mem.ptr)))[0 .. old_mem.len * @sizeOf(T)], ft.math.log2(@alignOf(T)), new_n, @returnAddress());
}
