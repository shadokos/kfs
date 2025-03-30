const BuddyAllocator = @import("buddy_allocator.zig").BuddyAllocator;
const paging = @import("paging.zig");
const builtin = @import("builtin");
const logger = @import("ft").log.scoped(.PFA);
const ft = @import("ft");
const Mutex = @import("../task/semaphore.zig").Mutex;

const max_order = 10;

pub fn PageFrameAllocator(comptime _Zones: type) type {
    switch (@typeInfo(_Zones)) {
        .@"enum" => {},
        else => @compileError("zones must be an enum"),
    }
    const nzones = @typeInfo(_Zones).@"enum".fields.len;
    return struct {
        total_space: u64 = undefined,

        zones: [nzones]?Zone = [1]?Zone{null} ** nzones,

        lock: Mutex = Mutex{},

        pub const Zone = struct {
            allocator: UnderlyingAllocator,
            begin: paging.PhysicalPtr,
            size: paging.PhysicalUsize,
        };

        pub const Zones = _Zones;

        pub const UnderlyingAllocator = BuddyAllocator(max_order);

        pub const Error = UnderlyingAllocator.Error;

        const Self = @This();

        pub fn init(_total_space: u64) Self {
            return Self{ .total_space = _total_space };
        }

        pub fn init_zone(
            self: *Self,
            zone: Zones,
            begin: paging.PhysicalPtr,
            size: paging.PhysicalUsize,
            allocator: ft.mem.Allocator,
        ) void {
            const _allocator = UnderlyingAllocator.init(
                @truncate(@min(self.total_space -| begin, size) / @sizeOf(paging.page)),
                allocator,
            );

            self.lock.acquire();
            defer self.lock.release();

            self.zones[@intFromEnum(zone)] = .{
                .allocator = _allocator,
                .begin = begin,
                .size = size,
            };
        }

        pub fn alloc_pages_zone(self: *Self, zone: Zones, n: usize) Error!paging.PhysicalPtr {
            self.lock.acquire();
            defer self.lock.release();

            inline for (0..nzones) |z| {
                if (self.zones[z]) |*unwrapped| {
                    if (z >= @intFromEnum(zone)) {
                        if (unwrapped.allocator.alloc_pages(n)) |v| {
                            return v * paging.page_size + unwrapped.begin;
                        } else |_| {}
                    }
                }
            }
            return Error.NotEnoughSpace;
        }

        pub fn alloc_pages(self: *Self, n: usize) Error!paging.PhysicalPtr {
            return self.alloc_pages_zone(@enumFromInt(0), n);
        }

        pub fn alloc_pages_hint(self: *Self, zone: Zones, n: usize) Error!paging.PhysicalPtr {
            self.lock.acquire();
            defer self.lock.release();

            inline for (0..nzones) |z| {
                if (self.zones[z]) |*unwrapped| {
                    if (z >= @intFromEnum(zone)) {
                        if (unwrapped.allocator.alloc_pages_hint(n)) |v| {
                            return v * paging.page_size + unwrapped.begin;
                        }
                    }
                }
            }
            return Error.NotEnoughSpace;
        }

        pub fn free_pages(self: *Self, ptr: paging.PhysicalPtr, n: usize) !void {
            self.lock.acquire();
            defer self.lock.release();

            inline for (0..nzones) |z| {
                if (self.zones[z]) |*unwrapped| {
                    if (ptr >= unwrapped.begin and ptr < unwrapped.begin + unwrapped.size) {
                        if (ptr + n * paging.page_size > unwrapped.begin + unwrapped.size) {
                            @panic("cross zone free_pages");
                        }
                        return unwrapped.allocator.free_pages(
                            @truncate((ptr - unwrapped.begin) / @sizeOf(paging.page)),
                            n,
                        );
                    }
                }
            }
            return Error.OutOfBounds;
        }

        pub fn get_page_frame_descriptor(self: *Self, ptr: paging.PhysicalPtr) !*paging.page_frame_descriptor {
            inline for (0..nzones) |z| {
                if (self.zones[z]) |*unwrapped| {
                    if (ptr >= unwrapped.begin and ptr < unwrapped.begin + unwrapped.size) {
                        return unwrapped.allocator.frame_from_idx(
                            @truncate((ptr - unwrapped.begin) / @sizeOf(paging.page)),
                        );
                    }
                }
            }
            return Error.OutOfBounds;
        }

        pub fn print(self: *Self) void {
            inline for (0..nzones) |z| {
                if (self.zones[z]) |*unwrapped| {
                    @import("../tty/tty.zig").printk("{s}:\n", .{@tagName(@as(Zones, @enumFromInt(z)))});
                    unwrapped.allocator.print();
                }
            }
        }
    };
}
