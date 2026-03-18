const std = @import("std");
const Alignment = std.mem.Alignment;
const printk = @import("../../../tty/tty.zig").printk;
const PageAllocator = @import("../../page_allocator.zig");
const paging = @import("../../paging.zig");
const pfd_t = paging.page_frame_descriptor;
const BitMap = @import("../../../misc/bitmap.zig").BitMap;
const mapping = @import("../../mapping.zig");
const Mutex = @import("../../../task/semaphore.zig").Mutex;

const Slab = @import("slab.zig");
const SlabState = @import("slab.zig").SlabState;

// DEPRECATED
const logger = std.log.scoped(.cache);

const CACHE_NAME_LEN = 20;

pub const Cache = struct {
    const Self = @This();
    pub const Error = error{ InitializationFailed, AllocationFailed };
    pub const AllocError = Error || Slab.Error || PageAllocator.Error;

    next: ?*Cache = null,
    prev: ?*Cache = null,
    slab_full: ?Slab = null,
    slab_partial: ?Slab = null,
    slab_empty: ?Slab = null,
    page_allocator: PageAllocator = undefined,
    pages_per_slab: usize = 0,
    name: [CACHE_NAME_LEN]u8 = undefined,
    nb_slab: usize = 0,
    nb_active_slab: usize = 0,
    obj_per_slab: u16 = 0,
    size_obj: usize = 0,
    align_obj: usize = 0,
    lock: Mutex = .{},

    pub fn init(
        name: []const u8,
        page_allocator: PageAllocator,
        obj_size: usize,
        obj_align: usize,
        order: u5,
    ) Error!Cache {
        var new = Cache{
            .page_allocator = page_allocator,
            .pages_per_slab = @as(usize, 1) << order,
            .size_obj = std.mem.alignForward(usize, obj_size, obj_align),
            .align_obj = obj_align,
        };

        const total = paging.page_size * new.pages_per_slab;
        new.obj_per_slab = @intCast(total / new.size_obj);

        if (new.obj_per_slab == 0 or new.obj_per_slab >= (1 << 16))
            return Error.InitializationFailed;

        const name_len = @min(name.len, CACHE_NAME_LEN);
        @memset(new.name[0..CACHE_NAME_LEN], 0);
        @memcpy(new.name[0..name_len], name[0..name_len]);
        return new;
    }

    // Slab list management ----------------------------------------------------
    //
    fn unlink(self: *Self, slab: Slab, from: SlabState) void {
        if (slab.prev()) |prev| {
            prev.set_next(slab.next());
        } else switch (from) {
            .Empty => self.slab_empty = slab.next(),
            .Partial => self.slab_partial = slab.next(),
            .Full => self.slab_full = slab.next(),
        }
        if (slab.next()) |next| next.set_prev(slab.prev());
    }

    fn link(self: *Self, slab: Slab, state: SlabState) void {
        switch (state) {
            .Empty => {
                slab.set_next(self.slab_empty);
                self.slab_empty = slab;
            },
            .Partial => {
                slab.set_next(self.slab_partial);
                self.slab_partial = slab;
            },
            .Full => {
                slab.set_next(self.slab_full);
                self.slab_full = slab;
            },
        }
        if (slab.next()) |next| Slab.from_pfd(next.pfd).set_prev(slab);
        slab.set_prev(null);
    }

    // Unsafe methods implement the logic without thread safety.
    // Each unsafe_xxx method correspond to a xxx method which simply calls unsafe_xxx wrapped by mutex lock/unlock.
    // This is a workaround to prevent deadlocks
    //
    pub fn unsafe_move_slab(self: *Self, slab: Slab, from: SlabState, to: SlabState) void {
        self.unlink(slab, from);
        self.link(slab, to);
    }

    pub fn unsafe_grow(self: *Self, nb_slab: usize) PageAllocator.Error!void {
        for (0..nb_slab) |_| {
            const page = try self.page_allocator.alloc_pages(self.pages_per_slab);
            const slab: Slab = Slab.init_pfds(page, self);
            const base = slab.base_addr();

            for (0..self.obj_per_slab) |i| {
                const obj_addr = base + (i * self.size_obj);
                const next_addr = if (i + 1 < self.obj_per_slab) base + ((i + 1) * self.size_obj) else 0;
                const obj_ptr: *usize = @ptrFromInt(obj_addr);
                obj_ptr.* = Slab.encode_ptr(obj_addr, next_addr);
            }
            slab.set_next_free(base);

            self.link(slab, SlabState.Empty);
            self.nb_slab += 1;
        }
    }

    fn unsafe_shrink(self: *Self) void {
        while (self.slab_empty) |slab| {
            self.unlink(slab, SlabState.Empty);
            const base_ptr: paging.VirtualPagePtr = @ptrFromInt(slab.base_addr());
            slab.reset_pfds(self.pages_per_slab);
            self.page_allocator.free_pages(base_ptr, self.pages_per_slab);
            self.nb_slab -= 1;
        }
    }

    fn unsafe_available_chunks(self: *Cache) usize {
        var ret: usize = 0;
        var partials = self.slab_partial;
        while (partials) |p| : (partials = p.next()) {
            ret += self.obj_per_slab - p.in_use();
        }
        var empty = self.slab_empty;
        while (empty) |e| : (empty = e.next()) {
            ret += self.obj_per_slab;
        }
        return ret;
    }

    fn unsafe_prepare_alloc(self: *Self, count: usize) !void {
        const available = self.available_chunks();
        if (available >= count)
            return;
        const needed = count - available;
        const slabs_needed = std.math.divCeil(usize, needed, self.obj_per_slab) catch unreachable;
        try self.unsafe_grow(slabs_needed);
    }

    fn unsafe_alloc_one(self: *Self) AllocError!*usize {
        const slab: ?Slab = if (self.slab_partial) |slab| slab else if (self.slab_empty) |slab| slab else null;
        if (slab) |s| {
            const obj_addr = s.next_free();
            if (obj_addr == 0) return Slab.Error.SlabFull;

            const is_empty = s.in_use() == 0;

            const obj_ptr: *usize = @ptrFromInt(obj_addr);
            const new_next = Slab.decode_ptr(obj_addr, obj_ptr.*);
            s.set_next_free(new_next);
            s.set_in_use(s.in_use() + 1);
            // Overwrite the freelist encoding so that double-free detection in
            // unsafe_free doesn't misread leftover freelist data as evidence the
            // slot is already free.  ~0 decodes to an address outside any slab.
            obj_ptr.* = Slab.encode_ptr(obj_addr, ~@as(usize, 0));

            if (is_empty) {
                self.unsafe_move_slab(s, SlabState.Empty, SlabState.Partial);
            } else if (s.next_free() == 0) {
                self.unsafe_move_slab(s, SlabState.Partial, SlabState.Full);
            }

            return @ptrFromInt(obj_addr);
        } else {
            try self.unsafe_grow(1);
            return self.unsafe_alloc_one();
        }
    }

    pub fn unsafe_free(_: *Self, ptr: *usize) Slab.Error!void {
        const obj_addr = @intFromPtr(ptr);
        const slab = Slab.resolve_head(@ptrCast(ptr)) catch return Slab.Error.InvalidArgument;

        const cache = slab.cache();
        const base = slab.base_addr();
        const slab_end = base + cache.size_obj * cache.obj_per_slab;

        if (obj_addr < base or obj_addr >= slab_end)
            return Slab.Error.InvalidArgument;
        if ((obj_addr - base) % cache.size_obj != 0)
            return Slab.Error.InvalidArgument;

        // Double-free detection: decode the stored value; if it decodes to 0
        // (null sentinel) or a valid aligned object address in this slab, the
        // slot is already in the freelist.
        const obj_ptr: *usize = @ptrFromInt(obj_addr);
        const decoded = Slab.decode_ptr(obj_addr, obj_ptr.*);
        if (decoded == 0 or (decoded >= base and decoded < slab_end and (decoded - base) % cache.size_obj == 0))
            return Slab.Error.DoubleFree;

        const was_full = slab.next_free() == 0;
        slab.set_in_use(slab.in_use() - 1);

        obj_ptr.* = Slab.encode_ptr(obj_addr, slab.next_free());
        slab.set_next_free(obj_addr);

        if (was_full) {
            cache.unsafe_move_slab(slab, SlabState.Full, SlabState.Partial);
        } else if (slab.in_use() == 0) {
            cache.unsafe_move_slab(slab, SlabState.Partial, SlabState.Empty);
        }
    }

    // Thread safe wrapper
    //
    pub fn move_slab(self: *Self, slab: Slab, from: SlabState, to: SlabState) void {
        self.lock.acquire();
        defer self.lock.release();
        return self.unsafe_move_slab(slab, from, to);
    }

    pub fn grow(self: *Self, nb_slab: usize) PageAllocator.Error!void {
        self.lock.acquire();
        defer self.lock.release();
        return self.unsafe_grow(nb_slab);
    }

    pub fn shrink(self: *Self) void {
        self.lock.acquire();
        defer self.lock.release();
        return self.unsafe_shrink();
    }

    pub fn available_chunks(self: *Self) usize {
        self.lock.acquire();
        defer self.lock.release();
        return self.unsafe_available_chunks();
    }

    pub fn prepare_alloc(self: *Self, count: usize) !void {
        self.lock.acquire();
        defer self.lock.release();
        return unsafe_prepare_alloc(count);
    }

    pub fn alloc_one(self: *Self) AllocError!*usize {
        self.lock.acquire();
        defer self.lock.release();
        return self.unsafe_alloc_one();
    }

    pub fn free(self: *Self, ptr: *usize) Slab.Error!void {
        self.lock.acquire();
        defer self.lock.release();
        return self.unsafe_free(ptr);
    }
    //
    // End of thread safe methods

    pub fn has_obj(self: *Self, obj: *usize) bool {
        const slab = Slab.resolve_head(@intFromPtr(obj)) catch return false;
        return slab.cache() == self;
    }

    pub fn debug(self: *Self) void {
        var nb_slab_empty: usize = 0;
        var nb_slab_partial: usize = 0;
        var nb_slab_full: usize = 0;
        var object_in_use: usize = 0;

        var head: ?Slab = self.slab_empty;
        while (head) |slab| : (nb_slab_empty += 1) head = slab.next();
        head = self.slab_partial;
        while (head) |slab| : (nb_slab_partial += 1) {
            head = slab.next();
            object_in_use += slab.in_use();
        }
        head = self.slab_full;
        while (head) |slab| : (nb_slab_full += 1) head = slab.next();

        object_in_use += (nb_slab_full * self.obj_per_slab);

        var name_len: usize = 1;
        for (self.name) |c| {
            if (c == 0) break else name_len += 1;
        }
        printk("\x1b[31m{s}\x1b[0m: ", .{self.name});
        for (name_len..@max(name_len, CACHE_NAME_LEN)) |_| printk(" ", .{});
        printk("{d: >5} ", .{self.size_obj});
        printk("{d: >5} ", .{self.obj_per_slab});
        printk("{d: >5} ", .{object_in_use});
        printk("{d: >5} ", .{self.pages_per_slab});
        printk("{d: >6} ", .{self.nb_slab});
        printk("{d: >6} ", .{nb_slab_empty});
        printk("{d: >6} ", .{nb_slab_partial});
        printk("{d: >5} ", .{nb_slab_full});
        printk("\n", .{});
    }

    fn vtable_alloc(ctx: *anyopaque, len: usize, alignment: Alignment, ret_addr: usize) ?[*]u8 {
        const self: *Self = @ptrCast(@alignCast(ctx));
        const alignment_bytes = alignment.toByteUnits();
        if (alignment_bytes > self.align_obj)
            @panic("Invalid alignment for slab allocator cache");
        _ = ret_addr;
        if (len != self.size_obj) {
            return null;
        }
        return @ptrCast(self.alloc_one() catch null);
    }

    fn vtable_resize(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *Self = @ptrCast(@alignCast(ctx));
        const alignment_bytes = alignment.toByteUnits();
        if (alignment_bytes > self.align_obj)
            @panic("Invalid alignment for slab allocator cache");
        _ = ret_addr;
        _ = memory;
        return new_len == self.size_obj;
    }

    fn vtable_remap(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        _ = ctx;
        _ = memory;
        _ = alignment;
        _ = new_len;
        _ = ret_addr;
        // Slab allocator doesn't support remapping
        return null;
    }

    fn vtable_free(ctx: *anyopaque, memory: []u8, alignment: Alignment, ret_addr: usize) void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        const alignment_bytes = alignment.toByteUnits();
        if (alignment_bytes > self.align_obj)
            @panic("Invalid alignment for slab allocator cache");
        _ = ret_addr;

        self.free(@ptrCast(@alignCast(memory.ptr))) catch @panic("invalid free");
    }

    const vTable = std.mem.Allocator.VTable{
        .alloc = &vtable_alloc,
        .resize = &vtable_resize,
        .remap = &vtable_remap,
        .free = &vtable_free,
    };

    pub fn allocator(self: *Self) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &vTable };
    }
};

pub const GlobalCache = struct {
    const Self = @This();

    cache: Cache = Cache{},
    lock: Mutex = Mutex{},

    pub fn init(allocator: PageAllocator) !GlobalCache {
        return .{ .cache = try Cache.init("global", allocator, @sizeOf(Cache), @alignOf(Cache), 0) };
    }

    pub fn create(
        self: *Self,
        name: []const u8,
        allocator: PageAllocator,
        obj_size: usize,
        obj_align: usize,
        order: u5,
    ) !*Cache {
        self.lock.acquire();
        defer self.lock.release();

        var cache: *Cache = @ptrCast(@alignCast(self.cache.alloc_one() catch |e| return e));

        cache.* = try Cache.init(name, allocator, obj_size, obj_align, order);

        cache.next = self.cache.next;
        if (self.cache.next) |next| next.prev = cache;
        self.cache.next = cache;

        return cache;
    }

    pub fn destroy(self: *Self, cache: *Cache) void {
        self.lock.acquire();
        defer self.lock.release();

        cache.shrink();
        var lst: ?Slab = cache.slab_full;

        while (lst) |slab| {
            lst = slab.next();
            slab.reset_pfds(cache.pages_per_slab);
            cache.page_allocator.free_pages(@ptrFromInt(slab.base_addr()), cache.pages_per_slab);
        }
        lst = cache.slab_partial;
        while (lst) |slab| {
            lst = slab.next();
            slab.reset_pfds(cache.pages_per_slab);
            cache.page_allocator.free_pages(@ptrFromInt(slab.base_addr()), cache.pages_per_slab);
        }
        if (cache.prev) |prev| prev.next = cache.next else self.cache.next = cache.next;
        if (cache.next) |next| next.prev = cache.prev;
        self.cache.free(@ptrCast(cache)) catch unreachable;
    }

    pub fn print(self: *Self) void {
        printk(" " ** (CACHE_NAME_LEN + 1), .{});
        printk(" \x1b[36msize\x1b[0m", .{});
        printk("   \x1b[36mo/s\x1b[0m", .{});
        printk("  \x1b[36mact.\x1b[0m", .{});
        printk("   \x1b[36mp/s\x1b[0m", .{});
        printk("  \x1b[36mslabs\x1b[0m", .{});
        printk("  \x1b[36mempty\x1b[0m", .{});
        printk("  \x1b[36mpart.\x1b[0m", .{});
        printk("  \x1b[36mfull\x1b[0m", .{});
        printk("\n", .{});
        var node: ?*Cache = self.cache.next;
        while (node) |n| : (node = n.next) n.debug();
        self.cache.debug();
    }
};
