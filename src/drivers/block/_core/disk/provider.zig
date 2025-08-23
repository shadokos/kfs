const std = @import("std");
const logger = std.log.scoped(.disk_provider);

const core = @import("../../core.zig");
const BlockDevice = core.BlockDevice;
const PartitionDevice = core.PartitionDevice;

pub const Disk = @import("disk.zig");

pub const MAX_DISK_PER_PROVIDER: u8 = 64;
const SlotManager = @import("../../../../misc/slot_manager.zig").SlotManager(Disk, MAX_DISK_PER_PROVIDER);

const CreateFn = fn (allocator: std.mem.Allocator, major: u8, minor: u8, params: *const void) anyerror!*BlockDevice;

const Self = @This();

create_fn: *const CreateFn,
major: u8,
slots: SlotManager = SlotManager{},

pub fn init(major: u8, create_fn: *const CreateFn) Self {
    return Self{
        .create_fn = create_fn,
        .major = major,
        .slots = SlotManager.init(),
    };
}

pub fn create_disk(self: *Self, allocator: std.mem.Allocator, params: *const void) !*Disk {
    const index: usize, const disk: *Disk = try self.slots.create(undefined);
    errdefer self.slots.destroy(@truncate(index)) catch {};

    // For now, a disk can contains up to 5 devices
    // 1 device for the whole disk, and up to 4 partition device
    const minor: u8 = @truncate(index * 5);
    disk.main = try self.create_fn(allocator, self.major, minor, params);

    return disk;
}

/// Destroy a disk or partition by its minor number
/// If a disk is destroyed, all its partitions are also destroyed
/// the return value is how many devices were destroyed (1 for partition, 1 + n for disk with n partitions)
pub fn destroy_disk(self: *Self, minor: u8) !u8 {
    var count: u8 = 0;

    const index = minor / 5;
    const disk = try self.slots.get(index);

    if (minor % 5 == 0) {
        for (disk.partitions) |partition| {
            if (partition) |p| {
                p.destroy();
                count += 1;
            }
        }
        disk.main.destroy();
        // If we're here, we know index is valid, we can safely ignore the error
        self.slots.destroy(@truncate(index)) catch unreachable;
        count += 1;
    } else {
        const partition_index = minor % 5 - 1;
        if (partition_index >= disk.partitions.len)
            return error.PartitionNotFound;
        if (disk.partitions[partition_index]) |partition| {
            partition.destroy();
            disk.partitions[partition_index] = null;
            return 1;
        }
        return error.PartitionNotFound;
    }
    return count;
}

pub fn get(self: *Self, minor: u8) !*BlockDevice {
    const index = minor / 5;
    const disk: *Disk = try self.slots.get(index);

    if (minor % 5 == 0)
        return disk.main;

    const partition_index = minor % 5 - 1;
    if (partition_index >= disk.partitions.len)
        return error.PartitionNotFound;
    if (disk.partitions[partition_index]) |partition|
        return partition;
    return error.PartitionNotFound;
}

pub fn deinit(self: *Self) void {
    for (0..MAX_DISK_PER_PROVIDER) |i| {
        const count = self.destroy_disk(@truncate(i * 5)) catch continue;
        logger.debug("Destroyed disk ({}:{}) with {} partitions", .{
            self.major,
            i * 5,
            count - 1,
        });
    }
}
