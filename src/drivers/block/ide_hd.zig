const std = @import("std");

const memory = @import("../../memory.zig");
const debug = @import("../../debug.zig");
const ide = @import("../ide/ide.zig");

const blk = @import("../../block/block.zig");
const STANDARD_BLOCK_SIZE = blk.STANDARD_BLOCK_SIZE;
const major_t = blk.major_t;
const minor_t = blk.minor_t;
const dev_t = blk.dev_t;
const GenDisk = blk.GenDisk;
const Partition = blk.Partition;

const registry = @import("../../block/registry.zig");

const big_allocator = memory.bigAlloc.allocator();
const small_allocator = memory.smallAlloc.allocator();

const Majors = enum(major_t) {
    IDE0_MAJOR = 3, // Primary channel of first controller
    IDE1_MAJOR = 22, // Secondary channel of first controller
    // TODO: Handle more than 2 channels
};

// Map channel index to major/name
const channel_to_major = [_]struct { major: major_t, name: []const u8 }{
    .{ .major = @intFromEnum(Majors.IDE0_MAJOR), .name = "ide0" }, // First controller, Primary
    .{ .major = @intFromEnum(Majors.IDE1_MAJOR), .name = "ide1" }, // First controller, Secondary
};

const MINORS: minor_t = 64; // 64 minors per channel (1 whole disk + partitions per drive)

const DriveInfo = ide.types.DriveInfo;
const Channel = ide.Channel;

const HdData = struct {
    drive_info: DriveInfo,
    channel: *Channel,
};

pub fn create_disk(channel: *Channel, info: DriveInfo) !*GenDisk {
    const disk = try blk.GenDisk.create(MINORS);

    // Calculate channel index: controller_index * 2 + channel_offset
    const controller_idx = channel.interface.index;
    const channel_offset: u8 = if (info.channel == .Primary) 0 else 1;
    const channel_idx = controller_idx * 2 + channel_offset;

    // Position within the channel (Master=0, Slave=1)
    const pos: u8 = if (info.position == .Master) 0 else 1;

    if (channel_idx >= channel_to_major.len) {
        return error.TooManyChannels;
    }

    disk.major = channel_to_major[channel_idx].major;
    disk.first_minor = pos * (MINORS / 2); // Each drive gets half the minors (32)

    // Calculate disk name: hda, hdb for first channel, hdc, hdd for second, etc.
    _ = std.fmt.bufPrint(&disk.name, "hd{c}", .{
        @as(u8, 'a' + (channel_idx * 2 + pos)),
    }) catch {};

    const data: *HdData = try small_allocator.create(HdData);
    errdefer small_allocator.destroy(data);

    data.drive_info = info;
    data.channel = channel;

    disk.private_data = @ptrCast(@alignCast(data));

    disk.vtable = &hd_ops;
    disk.features = .{
        .readonly = false,
        .removable = info.removable,
        .flushable = true,
        .trimable = false,
    };

    disk.max_transfer = 256; // 256 sectors max per operation
    disk.sector_size = info.capacity.sector_size;

    _ = disk.add_partition(0, info.capacity.sectors) catch |e| {
        std.log.debug("Failed to add whole partition: {s}", .{@errorName(e)});
        return e;
    };

    return disk;
}

pub fn destroy(disk: *GenDisk) void {
    if (disk.private_data == null) return;
    small_allocator.destroy(disk.private_data.?);
}

const hd_ops = blk.Operations{
    .physical_io = physical_io,
    .destroy = destroy,
};

fn probe() u32 {
    var count: u32 = 0;
    for (ide.channels) |*channel| {
        for ([_]ide.Channel.DrivePosition{ .Master, .Slave }) |position| {
            if (ide.ata.detectDrive(channel, position)) |info| {
                // // TODO: Maybe add some logging if an error occurs

                const model: []const u8 = std.mem.sliceTo(&info.model, 0);

                std.log.warn("Drive detected on channel {s} (IDE{d}), position {s}: {s}, {d} sectors", .{
                    @tagName(channel.channel_type),
                    channel.interface.index,
                    @tagName(position),
                    model,
                    info.capacity.sectors,
                });

                const disk = create_disk(channel, info) catch |err| {
                    std.log.err("Failed to create disk for drive {s}: {s}", .{ model, @errorName(err) });
                    continue;
                };

                // Calculate channel index for registry
                const controller_idx = channel.interface.index;
                const channel_offset: u8 = if (info.channel == .Primary) 0 else 1;
                const channel_idx = controller_idx * 2 + channel_offset;

                if (channel_idx < channel_to_major.len) {
                    const name = channel_to_major[channel_idx].name;
                    registry.register_block_dev(disk.major, name) catch {
                        continue;
                    };
                }

                count += 1;
            }
        }
    }
    return count;
}

/// Physical I/O function
fn physical_io(
    context: *anyopaque,
    sector: u32,
    count: u32,
    buffer: []u8,
    io_type: blk.IOType,
) blk.BlockError!void {
    const partition: *Partition = @ptrCast(@alignCast(context));

    if (partition.disk.private_data == null) return blk.BlockError.IoError;

    const sector_size = partition.translator.sector_size;
    const expected_size = count * sector_size;

    if (buffer.len < expected_size) {
        return blk.BlockError.BufferTooSmall;
    }

    const data: *HdData = @ptrCast(@alignCast(partition.disk.private_data.?));

    const op = ide.IDEOperation{
        .channel = data.channel,
        .position = data.drive_info.position,
        .lba = sector,
        .count = count,
        .buffer = switch (io_type) {
            .Read => .{ .read = buffer },
            .Write => .{ .write = buffer },
        },
        .io_type = io_type,
    };

    ide.performOperation(.ATA, &op) catch |err| {
        return switch (err) {
            ide.IDEError.OutOfBounds => blk.BlockError.OutOfBounds,
            else => blk.BlockError.IoError,
        };
    };
}

pub fn init() void {
    std.log.debug("probe: {d}", .{probe()});
}
