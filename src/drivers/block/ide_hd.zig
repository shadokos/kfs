const std = @import("std");

const memory = @import("../../memory.zig");
const debug = @import("../../debug.zig");
const ide = @import("../ide/ide.zig");

const log = std.log.scoped(.ide_hd);

const blk = @import("../../block/block.zig");
const STANDARD_BLOCK_SIZE = blk.STANDARD_BLOCK_SIZE;
const major_t = blk.major_t;
const minor_t = blk.minor_t;
const dev_t = blk.dev_t;
const GenDisk = blk.GenDisk;
const Partition = blk.Partition;

const registry = @import("../../block/registry.zig");

// Define Major numbers for standard IDE controllers
// - Primary Controller (IDE0): Major 3
// - Secondary Controller (IDE1): Major 22
// This follows Linux conventions for legacy IDE drivers.
const Majors = enum(major_t) {
    IDE0_MAJOR = 3, // Primary channel of first controller
    IDE1_MAJOR = 22, // Secondary channel of first controller
    // TODO: Handle more than 2 channels with dynamic major allocation when PCI IDE is implemented
};

// Map channel index to major/name
// This static mapping limits us to 2 controllers (4 drives max) which is standard for ISA IDE.
const channel_to_major = [_]struct { major: major_t, name: []const u8 }{
    .{ .major = @intFromEnum(Majors.IDE0_MAJOR), .name = "ide0" }, // First controller, Primary
    .{ .major = @intFromEnum(Majors.IDE1_MAJOR), .name = "ide1" }, // First controller, Secondary
};

const small_allocator = memory.smallAlloc.allocator();

// Number of minors per IDE channel (e.g., Major 3).
// We allocate 64 minors to allow for 2 drives of 32 partitions each.
// - Drive 0 (Master): Minors 0-31
// - Drive 1 (Slave): Minors 32-63
const MINORS: minor_t = 64;

const DriveInfo = ide.types.DriveInfo;
const Channel = ide.Channel;

// Private data attached to the Generic Disk structure.
// This bridges the Block Device layer (Generic Disk) with the IDE Hardware layer.
const HdData = struct {
    drive_info: DriveInfo,
    channel: *Channel,
};

/// Create a GenDisk instance for a detected IDE drive.
///
/// - `channel`: The hardware channel (Primary/Secondary)
/// - `info`: Drive information detected during probe (Model, Capacity, etc.)
/// - `channel_idx`: Global index of the channel (0 for Primary, 1 for Secondary)
pub fn create_disk(channel: *Channel, info: DriveInfo, channel_idx: usize) !*GenDisk {
    const disk = try blk.GenDisk.create(MINORS);

    // Position within the channel (Master=0, Slave=1)
    const pos: u8 = if (info.position == .Master) 0 else 1;

    if (channel_idx >= channel_to_major.len) {
        return error.TooManyChannels;
    }

    disk.major = channel_to_major[channel_idx].major;

    // Offset for Slave drive minors.
    // If Master, starts at 0. If Slave, starts at 32.
    disk.first_minor = pos * (MINORS / 2);

    // Calculate disk name: hda, hdb for first channel, hdc, hdd for second, etc.
    // 'a' + (0*2 + 0) = 'a' (hda) -> Primary Master
    // 'a' + (0*2 + 1) = 'b' (hdb) -> Primary Slave
    // 'a' + (1*2 + 0) = 'c' (hdc) -> Secondary Master
    _ = std.fmt.bufPrint(&disk.name, "hd{c}", .{
        @as(u8, @intCast('a' + (channel_idx * 2 + pos))),
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

    disk.max_transfer = 256; // 256 sectors max per operation (Standard ATA limit for LBA28/48 usually chunked)
    disk.sector_size = info.capacity.sector_size;

    // Register the whole disk partition covering all sectors
    _ = disk.add_partition(0, info.capacity.sectors) catch |e| {
        log.debug("Failed to add whole partition: {s}", .{@errorName(e)});
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

/// Probes all IDE channels for connected drives.
/// Registers them as Block Devices using the `probe` -> `create_disk` -> `register` flow.
fn probe() u32 {
    var count: u32 = 0;
    for (ide.channels) |*channel| {
        for ([_]ide.Channel.DrivePosition{ .Master, .Slave }) |position| {
            // Attempt to detect a drive on this channel/position pair
            if (ide.ata.detectDrive(channel, position)) |info| {
                const model: []const u8 = std.mem.sliceTo(&info.model, 0);

                log.debug("Drive detected on channel {s} (IDE{d}), position {s}: {s}, {d} sectors", .{
                    @tagName(channel.channel_type),
                    channel.interface.index,
                    @tagName(position),
                    model,
                    info.capacity.sectors,
                });

                // Calculate global channel index for registry mapping
                const controller_idx = channel.interface.index;
                const channel_offset: u8 = if (info.channel == .Primary) 0 else 1;
                const channel_idx = controller_idx * 2 + channel_offset;

                const disk = create_disk(channel, info, channel_idx) catch |err| {
                    log.err("Failed to create disk for drive {s}: {s}", .{ model, @errorName(err) });
                    continue;
                };

                if (channel_idx < channel_to_major.len) {
                    const name = channel_to_major[channel_idx].name;
                    // Register the Major number.
                    // Note: We ignore EBUSY because the first drive (Master) registers the Major.
                    // The second drive (Slave) shares the SAME Major, so registration will fail with EBUSY.
                    registry.register_block_dev(disk.major, name) catch |err| {
                        if (err != error.EBUSY) {
                            log.err("Failed to register block device major {d}: {s}", .{
                                disk.major,
                                @errorName(err),
                            });
                        }
                    };
                }

                count += 1;
            }
        }
    }
    return count;
}

/// Physical I/O entry point called by the Block Layer.
/// Translates Block Layer requests (Sector/Count) into IDE ATA Commands.
fn physical_io(
    context: *anyopaque,
    sector: u32,
    count: u32,
    buffer: []u8,
    io_type: blk.IOType,
) blk.BlockError!void {
    // Context is the Partition instance calling for IO.
    // We assert alignment to catch any unsafe pointer casting issues early.
    std.debug.assert(std.mem.isAligned(@intFromPtr(context), @alignOf(Partition)));
    const partition: *Partition = @ptrCast(@alignCast(context));

    if (partition.disk.private_data == null) return blk.BlockError.IoError;

    const sector_size = partition.translator.sector_size;
    const expected_size = count * sector_size;

    if (buffer.len < expected_size) {
        return blk.BlockError.BufferTooSmall;
    }

    // Retrieve hardware-specific data (Channel, Position) from Generic Disk private data
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

    // Delegate the actual hardware I/O to the ATA protocol implementation
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
