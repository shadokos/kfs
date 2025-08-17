// src/storage/buffer_cache.zig
const std = @import("std");
const BlockDevice = @import("block_device.zig").BlockDevice;
const BlockError = @import("block_device.zig").BlockError;
const STANDARD_BLOCK_SIZE = @import("block_device.zig").STANDARD_BLOCK_SIZE;
const ArrayList = std.ArrayList;
const Mutex = @import("../../task/semaphore.zig").Mutex;
const allocator = @import("../../memory.zig").bigAlloc.allocator();
const logger = std.log.scoped(.buffer_cache);

pub const Buffer = struct {
    device: *BlockDevice,
    block: u32,
    data: []align(16) u8,
    flags: Flags,
    ref_count: u32 = 0,
    last_access: u64 = 0,
    lru_prev: ?*Buffer = null,
    lru_next: ?*Buffer = null,
    hash_next: ?*Buffer = null,

    pub const Flags = packed struct {
        valid: bool = false,
        dirty: bool = false,
        locked: bool = false,
        err: bool = false,
        uptodate: bool = false,
    };

    pub fn markDirty(self: *Buffer) void {
        self.flags.dirty = true;
    }

    pub fn markClean(self: *Buffer) void {
        self.flags.dirty = false;
    }

    pub fn isValid(self: *const Buffer) bool {
        return self.flags.valid and self.flags.uptodate;
    }
};

const HASH_SIZE = 256;
const MAX_BUFFERS = 1024;

pub const BufferCache = struct {
    hash_table: [HASH_SIZE]?*Buffer,
    lru_head: ?*Buffer = null,
    lru_tail: ?*Buffer = null,
    free_list: ArrayList(*Buffer),
    buffer_pool: []align(16) u8,
    buffers: []Buffer,
    mutex: Mutex = .{},
    stats: CacheStats = .{},

    pub const CacheStats = struct {
        hits: u64 = 0,
        misses: u64 = 0,
        evictions: u64 = 0,
        writebacks: u64 = 0,
    };

    const Self = @This();

    pub fn init() !Self {
        const buffer_pool_size = MAX_BUFFERS * STANDARD_BLOCK_SIZE;

        var cache = Self{
            .hash_table = [_]?*Buffer{null} ** HASH_SIZE,
            .free_list = ArrayList(*Buffer).init(allocator),
            .buffer_pool = try allocator.alignedAlloc(u8, 16, buffer_pool_size),
            .buffers = try allocator.alloc(Buffer, MAX_BUFFERS),
        };

        var offset: usize = 0;
        for (cache.buffers) |*buffer| {
            buffer.* = .{
                .device = undefined,
                .block = 0,
                .data = @alignCast(cache.buffer_pool[offset .. offset + STANDARD_BLOCK_SIZE]),
                .flags = .{},
            };
            try cache.free_list.append(buffer);
            offset += STANDARD_BLOCK_SIZE;
        }

        logger.info("Buffer cache initialized with {} buffers of {} bytes", .{ MAX_BUFFERS, STANDARD_BLOCK_SIZE });

        return cache;
    }

    pub fn deinit(self: *Self) void {
        self.flushAll() catch {};
        self.free_list.deinit();
        allocator.free(self.buffer_pool);
        allocator.free(self.buffers);
    }

    fn hash(device: *BlockDevice, block: u64) u32 {
        const device_ptr = @intFromPtr(device);
        return @truncate((device_ptr ^ block) % HASH_SIZE);
    }

    fn findInCache(self: *Self, device: *BlockDevice, block: u64) ?*Buffer {
        const index = hash(device, block);
        var current = self.hash_table[index];

        while (current) |buffer| {
            if (buffer.device == device and buffer.block == block) {
                self.stats.hits += 1;
                return buffer;
            }
            current = buffer.hash_next;
        }

        self.stats.misses += 1;
        return null;
    }

    fn addToLRU(self: *Self, buffer: *Buffer) void {
        buffer.lru_prev = null;
        buffer.lru_next = self.lru_head;

        if (self.lru_head) |head| {
            head.lru_prev = buffer;
        }
        self.lru_head = buffer;

        if (self.lru_tail == null) {
            self.lru_tail = buffer;
        }

        buffer.last_access = @import("../../timer.zig").get_utime_since_boot();
    }

    fn removeFromLRU(self: *Self, buffer: *Buffer) void {
        if (buffer.lru_prev) |prev| {
            prev.lru_next = buffer.lru_next;
        } else {
            self.lru_head = buffer.lru_next;
        }

        if (buffer.lru_next) |next| {
            next.lru_prev = buffer.lru_prev;
        } else {
            self.lru_tail = buffer.lru_prev;
        }

        buffer.lru_prev = null;
        buffer.lru_next = null;
    }

    fn evictLRU(self: *Self) !*Buffer {
        var current = self.lru_tail;

        while (current) |buffer| {
            if (buffer.ref_count == 0 and !buffer.flags.locked) {
                if (buffer.flags.dirty) {
                    try self.writeBack(buffer);
                }

                const index = hash(buffer.device, buffer.block);
                var hash_current = &self.hash_table[index];
                while (hash_current.*) |hash_buffer| {
                    if (hash_buffer == buffer) {
                        hash_current.* = hash_buffer.hash_next;
                        break;
                    }
                    hash_current = &hash_buffer.hash_next;
                }

                self.removeFromLRU(buffer);
                self.stats.evictions += 1;
                return buffer;
            }
            current = buffer.lru_prev;
        }

        return BlockError.NoFreeBuffers;
    }

    fn writeBack(self: *Self, buffer: *Buffer) !void {
        if (!buffer.flags.dirty) return;

        buffer.flags.locked = true;
        defer buffer.flags.locked = false;

        // Always write STANDARD_BLOCK_SIZE bytes
        try buffer.device.write(buffer.block, 1, buffer.data[0..STANDARD_BLOCK_SIZE]);
        buffer.flags.dirty = false;
        self.stats.writebacks += 1;
    }

    pub fn get(self: *Self, device: *BlockDevice, block: u32) !*Buffer {
        self.mutex.acquire();
        defer self.mutex.release();

        if (self.findInCache(device, block)) |buffer| {
            buffer.ref_count += 1;
            self.removeFromLRU(buffer);
            self.addToLRU(buffer);
            return buffer;
        }

        var buffer: *Buffer = undefined;
        if (self.free_list.items.len > 0) {
            buffer = self.free_list.pop().?;
        } else {
            buffer = try self.evictLRU();
        }

        buffer.device = device;
        buffer.block = block;
        buffer.flags = .{};
        buffer.ref_count = 1;

        const index = hash(device, block);
        buffer.hash_next = self.hash_table[index];
        self.hash_table[index] = buffer;

        self.addToLRU(buffer);

        buffer.flags.locked = true;
        defer buffer.flags.locked = false;

        // Always read STANDARD_BLOCK_SIZE bytes
        device.read(block, 1, buffer.data[0..STANDARD_BLOCK_SIZE]) catch |err| {
            buffer.flags.err = true;
            return err;
        };

        buffer.flags.valid = true;
        buffer.flags.uptodate = true;

        return buffer;
    }

    pub fn put(self: *Self, buffer: *Buffer) void {
        self.mutex.acquire();
        defer self.mutex.release();

        if (buffer.ref_count > 0) {
            buffer.ref_count -= 1;
        }
    }

    pub fn sync(self: *Self, buffer: *Buffer) !void {
        self.mutex.acquire();
        defer self.mutex.release();

        try self.writeBack(buffer);
    }

    pub fn flushDevice(self: *Self, device: *BlockDevice) !void {
        self.mutex.acquire();
        defer self.mutex.release();

        for (0..HASH_SIZE) |i| {
            var current = self.hash_table[i];
            while (current) |buffer| {
                if (buffer.device == device and buffer.flags.dirty) {
                    try self.writeBack(buffer);
                }
                current = buffer.hash_next;
            }
        }

        try device.flush();
    }

    pub fn flushAll(self: *Self) !void {
        self.mutex.acquire();
        defer self.mutex.release();

        for (0..HASH_SIZE) |i| {
            var current = self.hash_table[i];
            while (current) |buffer| {
                if (buffer.flags.dirty) {
                    try self.writeBack(buffer);
                }
                current = buffer.hash_next;
            }
        }
    }

    pub fn printStats(self: *Self) void {
        const hit_rate = if (self.stats.hits + self.stats.misses > 0)
            (self.stats.hits * 100) / (self.stats.hits + self.stats.misses)
        else
            0;

        logger.info("Buffer Cache Statistics:", .{});
        logger.info("  Hits: {} ({} %)", .{ self.stats.hits, hit_rate });
        logger.info("  Misses: {}", .{self.stats.misses});
        logger.info("  Evictions: {}", .{self.stats.evictions});
        logger.info("  Writebacks: {}", .{self.stats.writebacks});
        logger.info("  Cache size: {} buffers x {} bytes = {} KB", .{
            MAX_BUFFERS,
            STANDARD_BLOCK_SIZE,
            (MAX_BUFFERS * STANDARD_BLOCK_SIZE) / 1024,
        });
    }
};
