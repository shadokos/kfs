const std = @import("std");
const storage = @import("../../../storage/storage.zig");
const ide = @import("../../../drivers/ide/ide.zig");
const logger = std.log.scoped(.storage_benchmark);
const tsc = @import("../../../drivers/tsc/tsc.zig");

const allocator = @import("../../../memory.zig").bigAlloc.allocator();

pub const BenchmarkResult = struct {
    operation: Operation,
    block_size: u32,
    block_count: u32,
    total_bytes: u64,
    time_us: u64,
    throughput_mbps: f64,
    iops: f64,
    cache_hits: u64 = 0,
    cache_misses: u64 = 0,

    pub const Operation = enum {
        SequentialRead,
        SequentialWrite,
        RandomRead,
        RandomWrite,
        CachedRead,
        CachedWrite,
    };

    pub fn print(self: *const BenchmarkResult) void {
        logger.info("{s}:", .{@tagName(self.operation)});
        logger.info("  Blocks: {} x {} bytes", .{ self.block_count, self.block_size });
        logger.info("  Time: {} µs", .{self.time_us});
        logger.info("  Throughput: {d:.2} MB/s", .{self.throughput_mbps});
        logger.info("  IOPS: {d:.0}", .{self.iops});
        if (self.cache_hits > 0 or self.cache_misses > 0) {
            const hit_rate = if (self.cache_hits + self.cache_misses > 0)
                (self.cache_hits * 100) / (self.cache_hits + self.cache_misses)
            else
                0;
            logger.info("  Cache hit rate: {}%", .{hit_rate});
        }
    }
};

pub const BenchmarkSuite = struct {
    device_name: []const u8,
    start_block: u32,
    results: std.ArrayList(BenchmarkResult),

    const Self = @This();

    pub fn init(device_name: []const u8, start_block: u32) Self {
        return .{
            .device_name = device_name,
            .start_block = start_block,
            .results = std.ArrayList(BenchmarkResult).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.results.deinit();
    }

    pub fn benchmarkSequentialRead(self: *Self, block_count: u32) !void {
        const device = storage.findDevice(self.device_name) orelse return error.DeviceNotFound;
        const total_bytes = block_count * device.block_size;

        const buffer = try allocator.alloc(u8, total_bytes);
        defer allocator.free(buffer);

        const start_time = tsc.get_time_us();
        try device.read(self.start_block, block_count, buffer);
        const end_time = tsc.get_time_us();

        const elapsed_us = end_time - start_time;
        const result = BenchmarkResult{
            .operation = .SequentialRead,
            .block_size = device.block_size,
            .block_count = block_count,
            .total_bytes = total_bytes,
            .time_us = elapsed_us,
            .throughput_mbps = if (elapsed_us > 0)
                (@as(f64, @floatFromInt(total_bytes)) / @as(f64, @floatFromInt(elapsed_us)))
            else
                0,
            .iops = if (elapsed_us > 0)
                (@as(f64, @floatFromInt(block_count)) * 1_000_000) / @as(f64, @floatFromInt(elapsed_us))
            else
                0,
        };

        try self.results.append(result);
        result.print();
    }

    pub fn benchmarkSequentialWrite(self: *Self, block_count: u32) !void {
        const device = storage.findDevice(self.device_name) orelse return error.DeviceNotFound;

        if (!device.features.writable) {
            logger.warn("Device {s} is not writable", .{self.device_name});
            return;
        }

        const total_bytes = block_count * device.block_size;

        const buffer = try allocator.alloc(u8, total_bytes);
        defer allocator.free(buffer);

        for (buffer, 0..) |*b, i| {
            b.* = @truncate(i);
        }

        const start_time = tsc.get_time_us();
        try device.write(self.start_block, block_count, buffer);
        const end_time = tsc.get_time_us();

        const elapsed_us = end_time - start_time;
        const result = BenchmarkResult{
            .operation = .SequentialWrite,
            .block_size = device.block_size,
            .block_count = block_count,
            .total_bytes = total_bytes,
            .time_us = elapsed_us,
            .throughput_mbps = if (elapsed_us > 0)
                (@as(f64, @floatFromInt(total_bytes)) / @as(f64, @floatFromInt(elapsed_us)))
            else
                0,
            .iops = if (elapsed_us > 0)
                (@as(f64, @floatFromInt(block_count)) * 1_000_000) / @as(f64, @floatFromInt(elapsed_us))
            else
                0,
        };

        try self.results.append(result);
        result.print();
    }

    pub fn benchmarkRandomRead(self: *Self, operation_count: u32, max_block_offset: u32) !void {
        const device = storage.findDevice(self.device_name) orelse return error.DeviceNotFound;

        const buffer = try allocator.alloc(u8, device.block_size);
        defer allocator.free(buffer);

        var rng = std.Random.Xoroshiro128.init(@truncate(tsc.get_time_us()));

        const start_time = tsc.get_time_us();
        for (0..operation_count) |_| {
            const random_block = self.start_block + (rng.random().int(u32) % max_block_offset);
            try device.read(random_block, 1, buffer);
        }
        const end_time = tsc.get_time_us();

        const elapsed_us = end_time - start_time;
        const result = BenchmarkResult{
            .operation = .RandomRead,
            .block_size = device.block_size,
            .block_count = operation_count,
            .total_bytes = operation_count * device.block_size,
            .time_us = elapsed_us,
            .throughput_mbps = if (elapsed_us > 0)
                (@as(f64, @floatFromInt(operation_count * device.block_size)) / @as(f64, @floatFromInt(elapsed_us)))
            else
                0,
            .iops = if (elapsed_us > 0)
                (@as(f64, @floatFromInt(operation_count)) * 1_000_000) / @as(f64, @floatFromInt(elapsed_us))
            else
                0,
        };

        try self.results.append(result);
        result.print();
    }

    pub fn benchmarkCachedRead(self: *Self, block_count: u32, iterations: u32) !void {
        const device = storage.findDevice(self.device_name) orelse return error.DeviceNotFound;
        const cache = storage.getCache();

        const buffer = try allocator.alloc(u8, device.block_size);
        defer allocator.free(buffer);

        cache.stats = .{};

        const start_time = tsc.get_time_us();
        for (0..iterations) |_| {
            for (0..block_count) |i| {
                try storage.readCached(self.device_name, self.start_block + i, 1, buffer);
            }
        }
        const end_time = tsc.get_time_us();

        const elapsed_us = end_time - start_time;
        const total_operations = iterations * block_count;
        const result = BenchmarkResult{
            .operation = .CachedRead,
            .block_size = device.block_size,
            .block_count = total_operations,
            .total_bytes = total_operations * device.block_size,
            .time_us = elapsed_us,
            .throughput_mbps = if (elapsed_us > 0)
                (@as(f64, @floatFromInt(total_operations * device.block_size)) / @as(f64, @floatFromInt(elapsed_us)))
            else
                0,
            .iops = if (elapsed_us > 0)
                (@as(f64, @floatFromInt(total_operations)) * 1_000_000) / @as(f64, @floatFromInt(elapsed_us))
            else
                0,
            .cache_hits = cache.stats.hits,
            .cache_misses = cache.stats.misses,
        };

        try self.results.append(result);
        result.print();
    }

    pub fn compareResults(self: *Self) void {
        logger.info("=== Benchmark Comparison ===", .{});

        var best_seq_read: f64 = 0;
        var best_seq_write: f64 = 0;
        var best_random_iops: f64 = 0;
        var best_cached_iops: f64 = 0;

        for (self.results.items) |result| {
            switch (result.operation) {
                .SequentialRead => {
                    if (result.throughput_mbps > best_seq_read) {
                        best_seq_read = result.throughput_mbps;
                    }
                },
                .SequentialWrite => {
                    if (result.throughput_mbps > best_seq_write) {
                        best_seq_write = result.throughput_mbps;
                    }
                },
                .RandomRead => {
                    if (result.iops > best_random_iops) {
                        best_random_iops = result.iops;
                    }
                },
                .CachedRead => {
                    if (result.iops > best_cached_iops) {
                        best_cached_iops = result.iops;
                    }
                },
                else => {},
            }
        }

        logger.info("Best Sequential Read: {d:.2} MB/s", .{best_seq_read});
        logger.info("Best Sequential Write: {d:.2} MB/s", .{best_seq_write});
        logger.info("Best Random IOPS: {d:.0}", .{best_random_iops});
        logger.info("Best Cached IOPS: {d:.0}", .{best_cached_iops});
    }
};

pub fn runQuickBenchmark(device_name: []const u8) !void {
    logger.info("=== Running Quick Storage Benchmark on {s} ===", .{device_name});
    logger.warn("This will write to blocks 10000-11024", .{});

    var suite = BenchmarkSuite.init(device_name, 1000);
    defer suite.deinit();

    logger.info("\n--- Sequential Read (1MB) ---", .{});
    try suite.benchmarkSequentialRead(2048);

    logger.info("\n--- Sequential Write (1MB) ---", .{});
    try suite.benchmarkSequentialWrite(2048);

    logger.info("\n--- Random Read (100 ops) ---", .{});
    try suite.benchmarkRandomRead(100, 1000);

    logger.info("\n--- Cached Read (10 blocks, 10 iterations) ---", .{});
    try suite.benchmarkCachedRead(10, 10);

    suite.compareResults();
}

pub fn measureLatency(device_name: []const u8, iterations: u32) !void {
    const device = storage.findDevice(device_name) orelse return error.DeviceNotFound;

    const buffer = try allocator.alloc(u8, device.block_size);
    defer allocator.free(buffer);

    logger.info("=== Measuring I/O Latency ({} iterations) ===", .{iterations});

    var total_us: u64 = 0;
    var min_us: u64 = std.math.maxInt(u64);
    var max_us: u64 = 0;

    for (0..iterations) |_| {
        const start = tsc.get_time_us();
        try device.read(1000, 1, buffer);
        const end = tsc.get_time_us();

        const elapsed = end - start;
        total_us += elapsed;
        if (elapsed < min_us) min_us = elapsed;
        if (elapsed > max_us) max_us = elapsed;
    }

    const avg_us = total_us / iterations;

    logger.info("Direct I/O latency:", .{});
    logger.info("  Average: {} µs", .{avg_us});
    logger.info("  Min: {} µs", .{min_us});
    logger.info("  Max: {} µs", .{max_us});

    total_us = 0;
    min_us = std.math.maxInt(u64);
    max_us = 0;

    for (0..iterations) |_| {
        const start = tsc.get_time_us();
        try storage.readCached(device_name, 2000, 1, buffer);
        const end = tsc.get_time_us();

        const elapsed = end - start;
        total_us += elapsed;
        if (elapsed < min_us) min_us = elapsed;
        if (elapsed > max_us) max_us = elapsed;
    }

    const cached_avg_us = total_us / iterations;

    logger.info("Cached I/O latency:", .{});
    logger.info("  Average: {} µs", .{cached_avg_us});
    logger.info("  Min: {} µs", .{min_us});
    logger.info("  Max: {} µs", .{max_us});

    const cache = storage.getCache();
    cache.printStats();
}

pub fn stressTest(device_name: []const u8, duration_ms: u64) !void {
    const device = storage.findDevice(device_name) orelse return error.DeviceNotFound;

    if (!device.features.writable) {
        logger.warn("Device {s} is not writable, skipping stress test", .{device_name});
        return;
    }

    logger.info("=== Running Stress Test for {} ms ===", .{duration_ms});

    const buffer_size = device.block_size * 16;
    const buffer = try allocator.alloc(u8, buffer_size);
    defer allocator.free(buffer);

    var rng = std.Random.Xoroshiro128.init(42);
    rng.fill(buffer);

    const start_time = tsc.get_time_us();
    const end_time = start_time + (duration_ms * 1000);

    var operations: u64 = 0;
    var bytes_transferred: u64 = 0;
    var errors: u64 = 0;

    while (tsc.get_time_us() < end_time) {
        const is_write = rng.random().boolean();
        const block_count = rng.random().intRangeAtMost(u32, 1, 16);
        const start_block = 10000 + rng.random().intRangeAtMost(u64, 0, 1000);

        if (is_write) {
            device.write(start_block, block_count, buffer[0 .. block_count * device.block_size]) catch {
                errors += 1;
                continue;
            };
        } else {
            device.read(start_block, block_count, buffer[0 .. block_count * device.block_size]) catch {
                errors += 1;
                continue;
            };
        }

        operations += 1;
        bytes_transferred += block_count * device.block_size;
    }

    const actual_duration_us = tsc.get_time_us() - start_time;
    const throughput_mbps =
        @as(f64, @floatFromInt(bytes_transferred)) / @as(f64, @floatFromInt(actual_duration_us));
    const ops_per_sec =
        (@as(f64, @floatFromInt(operations)) * 1_000_000) / @as(f64, @floatFromInt(actual_duration_us));

    logger.info("Stress Test Results:", .{});
    logger.info("  Duration: {} µs", .{actual_duration_us});
    logger.info("  Operations: {}", .{operations});
    logger.info("  Bytes transferred: {}", .{bytes_transferred});
    logger.info("  Errors: {}", .{errors});
    logger.info("  Throughput: {d:.2} MB/s", .{throughput_mbps});
    logger.info("  Operations/sec: {d:.0}", .{ops_per_sec});

    storage.printDeviceStats(device_name);
}
