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

pub fn show_lsblk(writer: std.io.AnyWriter, filter: ?[]const u8) void {
    const BLOCK_SIZE = core.STANDARD_BLOCK_SIZE;

    var it = partitions.inorderIterator();
    while (it.next()) |entry| {
        const part = entry.key;

        // Only process whole disk entries (partno == 0)
        if (part.partno != 0) continue;

        const disk = part.disk;
        const disk_name = std.mem.sliceTo(&disk.name, 0);

        // If filter is set, check if this disk matches or contains the partition
        if (filter) |f| {
            // Check if filter matches disk name
            const matches_disk = std.mem.eql(u8, disk_name, f);
            // Check if filter matches any partition name
            var matches_partition = false;
            for (disk.partition_table.items) |p| {
                if (std.mem.eql(u8, std.mem.sliceTo(&p.name, 0), f)) {
                    matches_partition = true;
                    break;
                }
            }
            if (!matches_disk and !matches_partition) continue;
        }

        // Calculate disk size in bytes
        const whole_disk = disk.partition_table.items[0];
        const disk_sectors = whole_disk.total_blocks;
        const disk_bytes = @as(u64, disk_sectors) * BLOCK_SIZE;

        // Print disk header (like fdisk -l)
        _ = writer.print(
            "\nDisk {s}: {d} MiB, {d} bytes, {d} sectors\n",
            .{ disk_name, disk_bytes / (1024 * 1024), disk_bytes, disk_sectors },
        ) catch {};

        _ = writer.print(
            "Sector size: {d} bytes\n",
            .{disk.sector_size},
        ) catch {};

        // Print partition table header
        _ = writer.print(
            "\n{s: <12} {s: <4} {s: >10} {s: >10} {s: >10} {s: >6} {s: >2} {s}\n",
            .{ "Device", "Boot", "Start", "End", "Sectors", "Size", "Id", "Type" },
        ) catch {};

        // Print each partition (skip partition 0 = whole disk)
        for (disk.partition_table.items) |p| {
            if (p.partno == 0) continue;

            const start = p.translator.logical_offset;
            const sectors = p.total_blocks;
            const end = start + sectors - 1;
            const size_bytes = @as(u64, sectors) * BLOCK_SIZE;

            // Format size nicely
            var size_buf: [8]u8 = undefined;
            const size_str = formatSize(size_bytes, &size_buf);

            // Boot flag
            const boot_str: []const u8 = if (p.bootable) "*" else "";

            _ = writer.print(
                "{s: <12} {s: <4} {d: >10} {d: >10} {d: >10} {s: >6} {X:0>2} {s}\n",
                .{
                    std.mem.sliceTo(&p.name, 0),
                    boot_str,
                    start,
                    end,
                    sectors,
                    size_str,
                    @intFromEnum(p.partition_type),
                    p.partition_type.displayName(),
                },
            ) catch {};
        }
    }
}

/// Format bytes into human-readable size (K, M, G)
/// Returns a string like "512B", "1K", "2M", "3G", etc.
fn formatSize(bytes: u64, buf: []u8) []const u8 {
    const units = [_][]const u8{ "B", "K", "M", "G", "T" };
    var size: f64 = @floatFromInt(bytes);
    var unit_idx: usize = 0;

    while (size >= 1024 and unit_idx < units.len - 1) {
        size /= 1024;
        unit_idx += 1;
    }

    if (unit_idx == 0) {
        return std.fmt.bufPrint(buf, "{d}B", .{@as(u64, @intFromFloat(size))}) catch "?";
    } else {
        return std.fmt.bufPrint(buf, "{d:.0}{s}", .{ size, units[unit_idx] }) catch "?";
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
