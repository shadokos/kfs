const std = @import("std");

const core = @import("block.zig");
const dev_t = core.dev_t;
const udev_t = core.udev_t;
const major_t = core.major_t;
const minor_t = core.minor_t;

const Errno = @import("../errno.zig").Errno;

const allocator = @import("../memory.zig").smallAlloc.allocator();
const MAX_MAJOR = std.math.maxInt(major_t);

var majors: [MAX_MAJOR]?[]const u8 = .{null} ** MAX_MAJOR;

pub const MAJOR: major_t = 254;

var ida: struct {
    const FreeList = std.ArrayList(minor_t);

    next_id: minor_t = 0,
    free_list: FreeList = .empty,
} = .{};

const Treap = std.Treap(*core.Partition, compare);
const TreapNode = Treap.Node;

pub fn compare(a: *core.Partition, b: *core.Partition) std.math.Order {
    return std.math.order(a.devt.toInt(), b.devt.toInt());
}

var partitions = Treap{};

pub fn register_block_dev(major: major_t, name: []const u8) !void {
    if (majors[major]) |_| return Errno.EBUSY;
    majors[major] = name;
}

pub fn blkext_alloc_id() !minor_t {
    if (ida.free_list.items.len > 0) {
        return ida.free_list.pop() orelse unreachable;
    }
    if (ida.next_id >= MAX_MAJOR) {
        return Errno.ENOSPC;
    }
    const id = ida.next_id;
    ida.next_id += 1;
    return id;
}

pub fn blkext_free_id(devt: dev_t) void {
    // If not an Extended block device, nothing to do
    if (devt.major != MAJOR) return;

    // Kernel panic if we can't keep track of the freed ID
    _ = ida.free_list.append(allocator, devt.minor) catch
        std.log.err("Failed to keep track of Extended block devices ({d})", .{devt.toInt()});
}

pub fn show_block_dev(writer: std.io.AnyWriter) void {
    _ = writer.print("Block devices:\n", .{}) catch {};
    for (majors, 0..) |name, major| {
        if (name) |n| {
            _ = writer.print("{d: >4} {s}\n", .{ major, n }) catch {};
        }
    }
}

pub fn show_partitions(writer: std.io.AnyWriter) void {
    _ = writer.print(
        "{s: <6}\t{s: <4}\t{s: <4}\t{s: <10}\t{s}\n",
        .{ "id", "major", "minor", "#blocks", "name" },
    ) catch {};

    var it = partitions.inorderIterator();
    while (it.next()) |entry| {
        const part = entry.key;

        if (part.partno != 0) continue;

        for (part.disk.partition_table.items) |p| {
            _ = writer.print(
                "{d: >6}\t{d: >4}\t{d: >4}\t{d: >10}\t{s}\n",
                .{
                    p.devt.toInt(),
                    p.devt.major,
                    p.devt.minor,
                    p.total_blocks,
                    p.name,
                },
            ) catch {};
        }
    }
}

pub fn lookup_devt(name: []const u8, partno: minor_t) ?dev_t {
    var it = partitions.inorderIterator();
    while (it.next()) |entry| {
        const part = entry.key;
        const disk = part.disk;

        const disk_name = std.mem.sliceTo(&disk.name, 0);

        if (!std.mem.eql(u8, disk_name, name)) continue;

        // the lookup devt returns the devt even if the partitions doesn't exist yet
        if (partno < disk.minors) {
            return dev_t{ .major = disk.major, .minor = disk.first_minor + partno };
        }

        if (partno >= disk.partition_table.items.len)
            break;

        return disk.partition_table.items[partno].devt;
    }
    return null;
}

pub fn get_partition(devt: dev_t) ?*core.Partition {
    var dummy_part: core.Partition = undefined;
    dummy_part.devt = devt;
    const entry = partitions.getEntryFor(&dummy_part);
    if (entry.node) |n| {
        return n.key;
    }
    return null;
}

pub fn get_partition_by_name(name: []const u8) ?*core.Partition {
    var it = partitions.inorderIterator();
    while (it.next()) |entry| {
        const part = entry.key;
        if (std.mem.eql(u8, std.mem.sliceTo(&part.name, 0), name)) {
            return part;
        }
    }
    return null;
}

pub fn get_disk(devt: dev_t) ?*core.GenDisk {
    if (get_partition(devt)) |part| {
        return part.disk;
    }
    return null;
}

pub fn get_disk_by_name(name: []const u8) ?*core.GenDisk {
    if (get_partition_by_name(name)) |part| {
        return part.disk;
    }
    return null;
}

// The "block device" is mostly a vfs layer concept representing a partition
// Actually every instance of "block device" is represented by a partition
pub fn register_device(part: *core.Partition) !void {
    var entry = partitions.getEntryFor(part);
    if (entry.node) |_| return Errno.EEXIST;
    const node: *TreapNode = allocator.create(TreapNode) catch return Errno.ENOSPC;
    node.key = part;
    entry.set(node);
}

pub fn unregister_device(devt: dev_t) void {
    var dummy_part: core.Partition = undefined;
    dummy_part.devt = devt;
    var entry = partitions.getEntryFor(&dummy_part);
    if (entry.node) |n| {
        entry.set(null);
        allocator.destroy(n);
    }
}

pub fn init() void {
    register_block_dev(MAJOR, "blkext") catch unreachable;
}
