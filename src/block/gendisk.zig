const std = @import("std");

// const old_core = @import("../../core.zig");
// const types = old_core.types;

// const BlockDevice = old_core.BlockDevice;
// const PartitionDevice = old_core.PartitionDevice;
// const major_t = types.major_t;
// const minor_t = types.minor_t;

const registry = @import("registry.zig");

const core = @import("block.zig");
const Features = core.Features;
const Partition = core.Partition;
const Operations = core.Operations;
const dev_t = core.dev_t;
const major_t = core.major_t;
const minor_t = core.minor_t;

const PartitionList = std.ArrayList(*Partition);

// const allocator = @import("../memory.zig").smallAlloc.allocator();
const allocator = @import("../memory.zig").bigAlloc.allocator();

const DISK_NAME_LEN = 16;

const Self = @This();

// name of whole disk
// name: [DISK_NAME_LEN]u8,

name: [DISK_NAME_LEN]u8,
major: major_t,
// number of minors (whole disk + partitions)
// if =1, the disk can't be partitioned
minors: minor_t,
first_minor: minor_t,
max_transfer: u16, // Maximum logical blocks per transfer
features: Features,
partition_table: PartitionList = .empty,
vtable: ?*const Operations,
private_data: ?*void = null,
sector_size: u32 = 512, // Physical sector size in bytes

pub fn create(minors: minor_t) !*Self {
    const disk: *Self = try allocator.create(Self);

    disk.* = .{
        .name = .{0} ** DISK_NAME_LEN,
        .major = 0,
        .minors = minors,
        .first_minor = 0,
        .features = .{},
        .max_transfer = 0,
        // .whole_partition = null,
        // .partition_table = PartitionList.init(allocator),
        .vtable = null,
        .private_data = null,
    };
    return disk;
}

pub fn destroy(self: *Self) void {
    for (self.partition_table.items) |partition| {
        registry.unregister_device(partition.devt);
        partition.destroy();
        allocator.destroy(partition);
    }
    self.partition_table.deinit(allocator);
    if (self.vtable) |vtable| {
        vtable.destroy(self);
    }
    allocator.destroy(self);
}

// disk: *GenDisk,
// name: [PART_NAME_LEN]u8,
// translator: *BlockTranslator, // Handles physical/logical translation
// stats: Statistics = .{},
// readonly: bool = false,

pub fn add_partition(self: *Self, offset: u32, limit: u32) !*Partition {
    var name: [Partition.PART_NAME_LEN]u8 = .{0} ** Partition.PART_NAME_LEN;

    const name_len = brk: for (self.name, 0..) |c, i| {
        if (c == 0) break :brk i;
    } else self.name.len;

    const index = self.partition_table.items.len;
    if (index > 0) {
        _ = std.fmt.bufPrint(&name, "{s}{s}{}", .{
            self.name[0..name_len],
            if (std.ascii.isDigit(self.name[name_len - 1])) "p" else "",
            index,
        }) catch |e| {
            std.log.err("Failed to format partition name: {s}", .{@errorName(e)});
        };
    } else {
        name = self.name;
    }

    const partition: *Partition = try allocator.create(Partition);
    errdefer allocator.destroy(partition);

    partition.* = .{
        .partno = @truncate(index),
        .disk = self,
        .name = name,
        .readonly = false,
        .translator = undefined,
        .total_blocks = limit,
    };

    _ = try partition.alloc_devt();
    errdefer partition.free_devt();

    // // Create the appropriate translator
    partition.translator = try core.translator.create(allocator, self.sector_size);
    errdefer partition.translator.deinit();

    partition.translator.logical_offset = offset; // in logical blocks (512-byte blocks)
    partition.translator.logical_limit = limit; // if null, no limit, up to the end of disk

    const entry: **Partition = try self.partition_table.addOne(allocator);
    entry.* = partition;
    errdefer _ = self.partition_table.orderedRemove(self.partition_table.items.len - 1);

    try registry.register_device(partition);

    return partition;
}
