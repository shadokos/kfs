pub const types = @import("_core/types.zig");

pub const translator = @import("_core/translator.zig");
pub const BlockTranslator = translator.BlockTranslator;
pub const ScaledTranslator = translator.ScaledTranslator;
pub const IdentityTranslator = translator.IdentityTranslator;

pub const BlockDevice = @import("_core/block_device.zig");
pub const PartitionDevice = @import("devices/partition.zig");
pub const DiskProvider = @import("_core/disk/provider.zig");

// Standard logical block size for all block devices
pub const STANDARD_BLOCK_SIZE: u32 = 512;

const std = @import("std");
const logger = std.log.scoped(.blockdev);

pub fn init() void {
    const allocator = @import("../../memory.zig").bigAlloc.allocator();
    const BlockRam = @import("devices/ramdisk.zig");

    @import("../../memory.zig").pageFrameAllocator.print();
    var ram_provider: DiskProvider = DiskProvider.init(
        5,
        @ptrCast(&BlockRam.create),
    );

    for (1..5) |i| {
        const P = BlockRam.CreateParams;
        const Disk = @import("_core/disk/disk.zig");
        const disk: *Disk = ram_provider.create_disk(allocator, @ptrCast(
            &P{
                .size_mb = 5,
                .physical_block_size = 1024,
            },
        )) catch |err| {
            logger.err("Failed to create RAM disk: {s}", .{@errorName(err)});
            return;
        };

        logger.debug("Disk created: {d}:{d}", .{ disk.main.major, disk.main.minor });

        for (0..i) |j| {
            const info: PartitionDevice.PartitionInfo = .{
                .start_lba = j * 1000,
                .total_blocks = 1000,
                .active = false,
            };
            disk.partitions[j] = PartitionDevice.create(
                allocator,
                disk.main,
                info,
                @truncate(j),
            ) catch |err| {
                logger.err("Failed to create partition: {s}", .{@errorName(err)});
                return;
            };
            var buffer: [512]u8 = .{0} ** 512;
            for (&buffer, 0..) |*b, idx| {
                b.* = @truncate((idx % 26) + 'A');
            }
            disk.partitions[j].?.write(0, 1, &buffer) catch |err| {
                logger.err("Failed to write to partition: {s}", .{@errorName(err)});
                return;
            };
        }
    }

    defer @import("../../memory.zig").pageFrameAllocator.print();
    defer ram_provider.deinit();

    const buffer = allocator.alloc(u8, 5 * 1024 * 1024) catch {
        logger.err("Failed to allocate buffer for reading", .{});
        return;
    };
    defer allocator.free(buffer);
    @memset(buffer, 0);

    const first_disk = ram_provider.get(15) catch {
        logger.err("No disks found in RAM provider", .{});
        return;
    };
    first_disk.read(0, first_disk.total_blocks, buffer) catch |err| {
        logger.err("Failed to read from RAM disk: {s}", .{@errorName(err)});
        return;
    };

    logger.warn("Disk 0: blocks {d}, buffer len: {d}", .{ first_disk.total_blocks, buffer.len });
    const start: usize = @intFromPtr(buffer.ptr);
    const end: usize = start + buffer.len;
    const debug = @import("../../debug.zig");
    debug.memory_dump(start, end, start);
}
