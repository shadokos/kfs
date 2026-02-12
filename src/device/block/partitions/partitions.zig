const std = @import("std");

const blk = @import("../block.zig");
const GenDisk = @import("../gendisk.zig");
const STANDARD_BLOCK_SIZE = blk.STANDARD_BLOCK_SIZE;

const logger = std.log.scoped(.partitions);

/// Result of attempting to parse a partition table
pub const ParseResult = enum {
    /// Parser recognized and successfully parsed the format
    Recognized,
    /// Parser did not recognize this format (try next parser)
    NotRecognized,
};

/// Context passed to partition parsers
pub const ParseContext = struct {
    disk: *GenDisk,
    buffer: []u8,
};

/// Partition parser interface
pub const PartitionParser = struct {
    /// Human-readable name for logging
    name: []const u8,
    /// Priority for ordering (lower = tried first)
    /// GPT should be ~50, MBR should be ~100
    priority: u8,
    /// Parse function
    parse: *const fn (*ParseContext, []const u8) ParseResult,
};

// Parser Registration (comptime)

/// Tuple of all partition parser modules
/// Each module must export a `parser` constant of type `PartitionParser`
///
/// To add a new parser:
/// 1. Create the parser module
/// 2. Add it to this tuple
/// 3. The framework handles the rest at comptime
const parser_modules = .{
    @import("mbr.zig"),
    // Future: @import("gpt.zig"),
};

/// Comptime-sorted array of parsers by priority
const sorted_parsers = blk: {
    var parsers: [parser_modules.len]PartitionParser = undefined;

    // Extract parsers from modules
    for (parser_modules, 0..) |module, i| {
        parsers[i] = module.parser;
    }

    // Sort by priority (insertion sort at comptime)
    for (1..parsers.len) |i| {
        const key = parsers[i];
        var j: usize = i;
        while (j > 0 and parsers[j - 1].priority > key.priority) {
            parsers[j] = parsers[j - 1];
            j -= 1;
        }
        parsers[j] = key;
    }

    break :blk parsers;
};

// Public API

/// Scan a disk for partition tables
///
/// Reads sector 0 and tries each registered parser in priority order.
/// The first parser that recognizes the format will parse the partition table
/// and add partitions to the disk.
///
/// This function is safe to call even if no partition table exists -
/// it will simply return without adding any partitions.
pub fn scan(disk: *GenDisk) !void {
    // We need to read from the whole disk partition (partition 0)
    if (disk.partition_table.items.len == 0) {
        logger.warn("Cannot scan partitions: no whole disk partition", .{});
        return;
    }

    const whole_disk = disk.partition_table.items[0];

    // Allocate buffer for reading sectors
    var buffer: [STANDARD_BLOCK_SIZE]u8 = undefined;

    // Read sector 0
    whole_disk.read(0, 1, &buffer) catch |e| {
        logger.warn("Failed to read sector 0: {s}", .{@errorName(e)});
        return e;
    };

    logger.debug("Read sector 0 successfully, first bytes: {X:0>2} {X:0>2} ... last bytes: {X:0>2} {X:0>2}", .{
        buffer[0],
        buffer[1],
        buffer[510],
        buffer[511],
    });

    var ctx = ParseContext{
        .disk = disk,
        .buffer = &buffer,
    };

    // Try each parser in priority order
    for (sorted_parsers) |parser| {
        const result = parser.parse(&ctx, &buffer);
        if (result == .Recognized) {
            logger.info("Disk {s}: {s} partition table detected", .{
                std.mem.sliceTo(&disk.name, 0),
                parser.name,
            });
            return;
        }
    }

    logger.debug("Disk {s}: no partition table detected", .{
        std.mem.sliceTo(&disk.name, 0),
    });
}
