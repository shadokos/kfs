// src/drivers/ide/benchmark.zig
const std = @import("std");
const timer = @import("../../timer.zig");
const ide = @import("ide.zig");
const fast_io = @import("fast_io.zig");
const block = @import("../../block/block.zig");
const logger = std.log.scoped(.ide_benchmark);
const tsc = @import("../../tsc/tsc.zig");

const allocator = @import("../../memory.zig").bigAlloc.allocator();

// === BENCHMARK RESULTS ===

pub const BenchmarkResult = struct {
    mode: fast_io.IOMode,
    operation: Operation,
    block_size: u32,
    block_count: u32,
    total_bytes: u64,
    time_us: u64,
    throughput_mbps: f64,
    iops: f64,

    pub const Operation = enum {
        SequentialRead,
        SequentialWrite,
        RandomRead,
        RandomWrite,
    };

    pub fn print(self: *const BenchmarkResult) void {
        logger.info("{s} - {s}:", .{@tagName(self.mode), @tagName(self.operation)});
        logger.info("  Blocks: {} x {} bytes", .{self.block_count, self.block_size});
        logger.info("  Time: {} us", .{self.time_us});
        logger.info("  Throughput: {d:.2} MB/s", .{self.throughput_mbps});
        logger.info("  IOPS: {d:.0}", .{self.iops});
    }
};

// === BENCHMARK SUITE ===

pub const BenchmarkSuite = struct {
    device_name: []const u8,
    start_block: u64,
    results: std.ArrayList(BenchmarkResult),

    const Self = @This();

    pub fn init(device_name: []const u8, start_block: u64) Self {
        return .{
            .device_name = device_name,
            .start_block = start_block,
            .results = std.ArrayList(BenchmarkResult).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.results.deinit();
    }

    /// Run sequential read benchmark
    pub fn benchmarkSequentialRead(
        self: *Self,
        mode: fast_io.IOMode,
        block_count: u32,
    ) !void {
        const device = block.findDevice(self.device_name) orelse return error.DeviceNotFound;
        const total_bytes = block_count * device.block_size;

        var buffer = try allocator.alloc(u8, total_bytes);
        defer allocator.free(buffer);

        // Set I/O mode
        fast_io.setMode(mode);

        // Warm up cache
        try device.read(self.start_block, 1, buffer[0..device.block_size]);

        // Actual benchmark
        const start_time = tsc.get_time_us();
        try device.read(self.start_block, block_count, buffer);
        const end_time = tsc.get_time_us();

        const elapsed_us = end_time - start_time;
        const result = BenchmarkResult{
            .mode = mode,
            .operation = .SequentialRead,
            .block_size = device.block_size,
            .block_count = block_count,
            .total_bytes = total_bytes,
            .time_us = elapsed_us,
            .throughput_mbps = if (elapsed_us > 0)
                (@as(f64, @floatFromInt(total_bytes)) / @as(f64, @floatFromInt(elapsed_us)))
            else 0,
            .iops = if (elapsed_us > 0)
                (@as(f64, @floatFromInt(block_count)) * 1_000_000) / @as(f64, @floatFromInt(elapsed_us))
            else 0,
        };

        try self.results.append(result);
        result.print();
    }

    /// Run sequential write benchmark
    pub fn benchmarkSequentialWrite(
        self: *Self,
        mode: fast_io.IOMode,
        block_count: u32,
    ) !void {
        const device = block.findDevice(self.device_name) orelse return error.DeviceNotFound;

        if (!device.features.writable) {
            logger.warn("Device {s} is not writable", .{self.device_name});
            return;
        }

        const total_bytes = block_count * device.block_size;

        const buffer = try allocator.alloc(u8, total_bytes);
        defer allocator.free(buffer);

        // Fill with test pattern
        for (buffer, 0..) |*b, i| {
            b.* = @truncate(i);
        }

        // Set I/O mode
        fast_io.setMode(mode);

        // Actual benchmark
        const start_time = tsc.get_time_us();
        try device.write(self.start_block, block_count, buffer);
        const end_time = tsc.get_time_us();

        const elapsed_us = end_time - start_time;
        const result = BenchmarkResult{
            .mode = mode,
            .operation = .SequentialWrite,
            .block_size = device.block_size,
            .block_count = block_count,
            .total_bytes = total_bytes,
            .time_us = elapsed_us,
            .throughput_mbps = if (elapsed_us > 0)
                (@as(f64, @floatFromInt(total_bytes)) / @as(f64, @floatFromInt(elapsed_us)))
            else 0,
            .iops = if (elapsed_us > 0)
                (@as(f64, @floatFromInt(block_count)) * 1_000_000) / @as(f64, @floatFromInt(elapsed_us))
            else 0,
        };

        try self.results.append(result);
        result.print();
    }

    /// Run random read benchmark
    pub fn benchmarkRandomRead(
        self: *Self,
        mode: fast_io.IOMode,
        operation_count: u32,
        max_block_offset: u32,
    ) !void {
        const device = block.findDevice(self.device_name) orelse return error.DeviceNotFound;

        const buffer = try allocator.alloc(u8, device.block_size);
        defer allocator.free(buffer);

        // Set I/O mode
        fast_io.setMode(mode);

        // Generate random block numbers
        var rng = std.Random.Xoroshiro128.init(@truncate(tsc.get_time_us()));

        // Actual benchmark
        const start_time = tsc.get_time_us();
        for (0..operation_count) |_| {
            const random_block = self.start_block + (rng.random().int(u32) % max_block_offset);
            try device.read(random_block, 1, buffer);
        }
        const end_time = tsc.get_time_us();

        const elapsed_us = end_time - start_time;
        const result = BenchmarkResult{
            .mode = mode,
            .operation = .RandomRead,
            .block_size = device.block_size,
            .block_count = operation_count,
            .total_bytes = operation_count * device.block_size,
            .time_us = elapsed_us,
            .throughput_mbps = if (elapsed_us > 0)
                (@as(f64, @floatFromInt(operation_count * device.block_size)) / @as(f64, @floatFromInt(elapsed_us)))
            else 0,
            .iops = if (elapsed_us > 0)
                (@as(f64, @floatFromInt(operation_count)) * 1_000_000) / @as(f64, @floatFromInt(elapsed_us))
            else 0,
        };

        try self.results.append(result);
        result.print();
    }

    /// Compare results between different modes
    pub fn compareResults(self: *Self) void {
        logger.info("=== Benchmark Comparison ===", .{});

        // Group results by operation
        var seq_read_results = std.ArrayList(BenchmarkResult).init(allocator);
        defer seq_read_results.deinit();
        var seq_write_results = std.ArrayList(BenchmarkResult).init(allocator);
        defer seq_write_results.deinit();
        var rand_read_results = std.ArrayList(BenchmarkResult).init(allocator);
        defer rand_read_results.deinit();

        for (self.results.items) |result| {
            switch (result.operation) {
                .SequentialRead => seq_read_results.append(result) catch {},
                .SequentialWrite => seq_write_results.append(result) catch {},
                .RandomRead => rand_read_results.append(result) catch {},
                .RandomWrite => {},
            }
        }

        // Compare sequential read results
        if (seq_read_results.items.len > 1) {
            logger.info("Sequential Read Comparison:", .{});
            var best_throughput: f64 = 0;
            var best_mode: fast_io.IOMode = .Interrupt;

            for (seq_read_results.items) |result| {
                logger.info("  {s}: {d:.2} MB/s", .{@tagName(result.mode), result.throughput_mbps});
                if (result.throughput_mbps > best_throughput) {
                    best_throughput = result.throughput_mbps;
                    best_mode = result.mode;
                }
            }
            logger.info("  Best: {s} with {d:.2} MB/s", .{@tagName(best_mode), best_throughput});
        }

        // Compare sequential write results
        if (seq_write_results.items.len > 1) {
            logger.info("Sequential Write Comparison:", .{});
            var best_throughput: f64 = 0;
            var best_mode: fast_io.IOMode = .Interrupt;

            for (seq_write_results.items) |result| {
                logger.info("  {s}: {d:.2} MB/s", .{@tagName(result.mode), result.throughput_mbps});
                if (result.throughput_mbps > best_throughput) {
                    best_throughput = result.throughput_mbps;
                    best_mode = result.mode;
                }
            }
            logger.info("  Best: {s} with {d:.2} MB/s", .{@tagName(best_mode), best_throughput});
        }

        // Compare random read results
        if (rand_read_results.items.len > 1) {
            logger.info("Random Read Comparison:", .{});
            var best_iops: f64 = 0;
            var best_mode: fast_io.IOMode = .Interrupt;

            for (rand_read_results.items) |result| {
                logger.info("  {s}: {d:.0} IOPS", .{@tagName(result.mode), result.iops});
                if (result.iops > best_iops) {
                    best_iops = result.iops;
                    best_mode = result.mode;
                }
            }
            logger.info("  Best: {s} with {d:.0} IOPS", .{@tagName(best_mode), best_iops});
        }
    }
};

// === QUICK BENCHMARK ===

/// Run a quick benchmark comparing all modes
pub fn runQuickBenchmark(device_name: []const u8) !void {
    logger.info("=== Running Quick I/O Benchmark on {s} ===", .{device_name});
    logger.warn("This will write to blocks 10000-11024", .{});

    var suite = BenchmarkSuite.init(device_name, 10000);
    defer suite.deinit();

    const modes = [_]fast_io.IOMode{ .Interrupt, .Polling, .Adaptive };

    // Test sequential read (1MB)
    logger.info("\n--- Sequential Read (1MB) ---", .{});
    for (modes) |mode| {
        try suite.benchmarkSequentialRead(mode, 2048); // 2048 * 512 = 1MB
    }

    // Test sequential write (1MB)
    logger.info("\n--- Sequential Write (1MB) ---", .{});
    for (modes) |mode| {
        try suite.benchmarkSequentialWrite(mode, 2048);
    }

    // Test random read (100 operations)
    logger.info("\n--- Random Read (100 ops) ---", .{});
    for (modes) |mode| {
        try suite.benchmarkRandomRead(mode, 100, 1000);
    }

    // Show comparison
    suite.compareResults();

    // Recommend best mode based on results
    recommendBestMode(&suite);
}

/// Recommend the best I/O mode based on benchmark results
fn recommendBestMode(suite: *BenchmarkSuite) void {
    var polling_score: u32 = 0;
    var interrupt_score: u32 = 0;
    var adaptive_score: u32 = 0;

    for (suite.results.items) |result| {
        // Find best mode for each operation
        var best_for_op: fast_io.IOMode = .Interrupt;
        var best_metric: f64 = 0;

        for (suite.results.items) |r| {
            if (r.operation != result.operation) continue;

            const metric = if (result.operation == .RandomRead or result.operation == .RandomWrite)
                r.iops
            else
                r.throughput_mbps;

            if (metric > best_metric) {
                best_metric = metric;
                best_for_op = r.mode;
            }
        }

        // Award points to the best mode
        switch (best_for_op) {
            .Polling => polling_score += 1,
            .Interrupt => interrupt_score += 1,
            .Adaptive => adaptive_score += 1,
        }
    }

    logger.info("\n=== Recommendation ===", .{});

    if (adaptive_score >= polling_score and adaptive_score >= interrupt_score) {
        logger.info("Recommended mode: Adaptive (best overall performance)", .{});
        fast_io.setMode(.Adaptive);
    } else if (polling_score > interrupt_score) {
        logger.info("Recommended mode: Polling (best for low latency)", .{});
        fast_io.setMode(.Polling);
        fast_io.tuneForLatency();
    } else {
        logger.info("Recommended mode: Interrupt (best for power efficiency)", .{});
        fast_io.setMode(.Interrupt);
    }
}

// === LATENCY TEST ===

/// Measure I/O latency for single-block operations
pub fn measureLatency(device_name: []const u8, iterations: u32) !void {
    const device = block.findDevice(device_name) orelse return error.DeviceNotFound;

    const buffer = try allocator.alloc(u8, device.block_size);
    defer allocator.free(buffer);

    logger.info("=== Measuring I/O Latency ({} iterations) ===", .{iterations});

    const modes = [_]fast_io.IOMode{ .Interrupt, .Polling, .Adaptive };

    for (modes) |mode| {
        fast_io.setMode(mode);

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

        logger.info("{s} mode:", .{@tagName(mode)});
        logger.info("  Average: {} us", .{avg_us});
        logger.info("  Min: {} us", .{min_us});
        logger.info("  Max: {} us", .{max_us});
    }
}