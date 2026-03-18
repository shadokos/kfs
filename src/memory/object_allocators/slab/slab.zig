const std = @import("std");
const paging = @import("../../paging.zig");
const mapping = @import("../../mapping.zig");

const Cache = @import("cache.zig").Cache;
const pfd_t = paging.page_frame_descriptor;
const Slab = @This();

pub const SlabState = enum { Empty, Partial, Full };
pub const Error = error{ InvalidArgument, SlabFull, SlabCorrupted, DoubleFree };

var secret: usize = 0;

pub fn init_secret(s: usize) void {
    secret = s;
}

pub fn encode_ptr(own_addr: usize, next_addr: usize) usize {
    return own_addr ^ next_addr ^ secret;
}

pub fn decode_ptr(own_addr: usize, stored: usize) usize {
    return own_addr ^ stored ^ secret;
}

pfd: *pfd_t,

pub fn from_pfd(pfd: *pfd_t) Slab {
    return Slab{ .pfd = pfd };
}

pub fn from_page(ptr: paging.VirtualPagePtr) !Slab {
    return Slab{ .pfd = Slab.get_pfd(ptr) };
}

pub fn resolve_head(ptr: paging.VirtualPtr) !Slab {
    const pfd = mapping.get_page_frame_descriptor(
        @ptrFromInt((std.mem.alignBackward(usize, @intFromPtr(ptr), paging.page_size))),
    ) catch return error.InvalidArgument;
    switch (pfd.state) {
        .slab_head => return Slab{ .pfd = pfd },
        .slab_tail => return Slab{ .pfd = pfd.state.slab_tail.head },
        else => return error.InvalidArgument,
    }
}

// page frame descriptor lifecycle ---------------------------------------------

/// Setup head and tail PFDs for a newly allocated slab.
pub fn init_pfds(page_ptr: paging.VirtualPagePtr, c: *Cache) Slab {
    const head_pfd: *pfd_t = Slab.get_pfd(page_ptr) catch unreachable;
    head_pfd.state = .{
        .slab_head = .{ .cache = c, .in_use = 0, .next_free = 0, .page = page_ptr },
    };

    for (1..c.pages_per_slab) |i| {
        const page_addr: paging.VirtualPagePtr = @ptrFromInt(@intFromPtr(page_ptr) + (i * paging.page_size));
        const tail_pfd = Slab.get_pfd(page_addr) catch unreachable;
        tail_pfd.state = .{ .slab_tail = .{ .head = head_pfd } };
    }

    return Slab{ .pfd = head_pfd };
}

/// Reset all PFDs of this slab back to free state.
pub fn reset_pfds(self: Slab, pages_per_slab: usize) void {
    const base = self.base_addr();
    for (0..pages_per_slab) |i| {
        const page_addr: paging.VirtualPagePtr = @ptrFromInt(base + (i * paging.page_size));
        const pfd = Slab.get_pfd(page_addr) catch unreachable;
        pfd.state = .{ .other = 0 };
    }
}

// State management ------------------------------------------------------------

pub fn get_state(self: Slab) SlabState {
    if (self.pfd.state.slab_head.in_use == 0) return SlabState.Empty;
    if (self.pfd.state.slab_head.next_free == 0) return SlabState.Full;
    return SlabState.Partial;
}

pub fn in_use(self: Slab) u16 {
    return self.pfd.state.slab_head.in_use;
}

pub fn set_in_use(self: Slab, value: u16) void {
    self.pfd.state.slab_head.in_use = value;
}

pub fn base_addr(self: Slab) usize {
    return @intFromPtr(self.pfd.state.slab_head.page);
}

pub fn cache(self: Slab) *Cache {
    return self.pfd.state.slab_head.cache;
}

pub fn next_free(self: Slab) usize {
    return self.pfd.state.slab_head.next_free;
}

pub fn set_next_free(self: Slab, value: usize) void {
    self.pfd.state.slab_head.next_free = value;
}

// Linked list management ------------------------------------------------------

pub fn next(self: Slab) ?Slab {
    if (self.pfd.state.slab_head.next) |next_pfd| return Slab{ .pfd = next_pfd };
    return null;
}

pub fn prev(self: Slab) ?Slab {
    if (self.pfd.state.slab_head.prev) |prev_pfd| return Slab{ .pfd = prev_pfd };
    return null;
}

pub fn set_next(self: Slab, slab: ?Slab) void {
    self.pfd.state.slab_head.next = if (slab) |s| s.pfd else null;
}

pub fn set_prev(self: Slab, slab: ?Slab) void {
    self.pfd.state.slab_head.prev = if (slab) |s| s.pfd else null;
}

pub fn get_pfd(ptr: paging.VirtualPagePtr) !*pfd_t {
    return mapping.get_page_frame_descriptor(ptr) catch error.InvalidArgument;
}
