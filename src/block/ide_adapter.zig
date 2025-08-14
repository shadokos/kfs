// src/block/ide_adapter.zig
const std = @import("std");
const ide = @import("../drivers/ide/ide.zig");
const block = @import("block.zig");
const BlockDevice = block.BlockDevice;
const logger = std.log.scoped(.ide_block_adapter);

const allocator = @import("../memory.zig").smallAlloc.allocator();

// === IDE BLOCK DEVICE ADAPTER ===

pub const IDEBlockDevice = struct {
    base: BlockDevice,
    drive_index: usize,
    drive_info: ide.types.DriveInfo,

    // IDE-specific operations
    const ide_ops = BlockDevice.Operations{
        .read = ideRead,
        .write = ideWrite,
        .flush = ideFlush,
        .trim = null, // IDE doesn't support TRIM
        .get_info = ideGetInfo,
        .media_changed = ideMediaChanged,
        .revalidate = ideRevalidate,
    };

    const Self = @This();

    pub fn create(drive_index: usize) !*Self {
        const drive_info = ide.getDriveInfo(drive_index) orelse return error.InvalidDrive;

        const device = try allocator.create(Self);
        errdefer allocator.destroy(device);

        // Generate device name
        const device_name = try generateDeviceName(drive_index, drive_info);

        // Determine device type
        const device_type: BlockDevice.DeviceType = switch (drive_info.drive_type) {
            .ATA => .HardDisk,
            .ATAPI => .CDROM,
            else => .Unknown,
        };

        // Set features based on drive type
        const features = BlockDevice.Features{
            .readable = true,
            .writable = drive_info.drive_type == .ATA,
            .removable = drive_info.removable,
            .supports_flush = drive_info.drive_type == .ATA,
            .supports_trim = false, // Traditional IDE doesn't support TRIM
            .supports_barriers = false,
        };

        // Determine cache policy
        const cache_policy: BlockDevice.CachePolicy = if (drive_info.drive_type == .ATAPI)
            .NoCache // CD-ROMs typically don't benefit from write caching
        else
            .WriteBack; // Hard disks benefit from write-back caching

        device.* = .{
            .base = .{
                .name = device_name,
                .device_type = device_type,
                .block_size = drive_info.capacity.sector_size,
                .total_blocks = drive_info.capacity.sectors,
                .max_transfer = if (drive_info.drive_type == .ATA) 256 else 65535, // ATA: 256 sectors, ATAPI: varies
                .features = features,
                .ops = &ide_ops,
                .private_data = device,
                .cache_policy = cache_policy,
            },
            .drive_index = drive_index,
            .drive_info = drive_info,
        };

        return device;
    }

    pub fn destroy(self: *Self) void {
        allocator.destroy(self);
    }

    fn generateDeviceName(drive_index: usize, drive_info: ide.types.DriveInfo) ![16]u8 {
        var name: [16]u8 = [_]u8{0} ** 16;

        if (drive_info.drive_type == .ATAPI) {
            // CD-ROM devices: cd0, cd1, etc.
            const str = try std.fmt.bufPrint(&name, "cd{}", .{drive_index});
            name[str.len] = 0;
        } else {
            // Hard disk devices: hda, hdb, hdc, hdd (legacy naming)
            // or sd0, sd1, etc. (modern naming)
            const letter: u8 = @truncate('a' + drive_index);
            const str = try std.fmt.bufPrint(&name, "hd{c}", .{letter});
            name[str.len] = 0;
        }

        return name;
    }

    // === OPERATION IMPLEMENTATIONS ===

    fn ideRead(dev: *BlockDevice, start_block: u64, count: u32, buffer: []u8) block.Error!void {
        const self: *Self = @fieldParentPtr("base", dev);

        // Validate request
        if (start_block > std.math.maxInt(u32)) return block.Error.OutOfBounds;

        // Perform IDE read
        ide.read(
            self.drive_index,
            @truncate(start_block),
            @truncate(count),
            buffer,
            5000, // 5 second timeout
        ) catch |err| {
            dev.stats.errors += 1;
            return switch (err) {
                error.InvalidDrive => block.Error.DeviceNotFound,
                error.BufferTooSmall => block.Error.BufferTooSmall,
                error.OutOfBounds => block.Error.OutOfBounds,
                error.Timeout => block.Error.IoError,
                error.NoMedia => block.Error.MediaNotPresent,
                else => block.Error.IoError,
            };
        };
    }

    fn ideWrite(dev: *BlockDevice, start_block: u64, count: u32, buffer: []const u8) block.Error!void {
        const self: *Self = @fieldParentPtr("base", dev);

        // Check if device is writable
        if (self.drive_info.drive_type != .ATA) {
            return block.Error.WriteProtected;
        }

        // Validate request
        if (start_block > std.math.maxInt(u32)) return block.Error.OutOfBounds;

        // Perform IDE write
        ide.write(
            self.drive_index,
            @truncate(start_block),
            @truncate(count),
            buffer,
            5000, // 5 second timeout
        ) catch |err| {
            dev.stats.errors += 1;
            return switch (err) {
                error.InvalidDrive => block.Error.DeviceNotFound,
                error.BufferTooSmall => block.Error.BufferTooSmall,
                error.OutOfBounds => block.Error.OutOfBounds,
                error.Timeout => block.Error.IoError,
                // error.WriteProtected => block.Error.WriteProtected,
                else => block.Error.IoError,
            };
        };
    }

    fn ideFlush(dev: *BlockDevice) block.Error!void {
        const self: *Self = @fieldParentPtr("base", dev);

        // Only ATA drives support flush
        if (self.drive_info.drive_type != .ATA) {
            return;
        }

        // TODO: Implement ATA FLUSH CACHE command (0xE7)
        // For now, we assume writes are committed
    }

    fn ideGetInfo(dev: *BlockDevice) BlockDevice.DeviceInfo {
        const self: *Self = @fieldParentPtr("base", dev);

        // Extract model string
        const model_len = blk: {
            for (self.drive_info.model, 0..) |c, idx| {
                if (c == 0) break :blk idx;
            }
            break :blk self.drive_info.model.len;
        };

        return .{
            .vendor = "Generic",
            .model = self.drive_info.model[0..model_len],
            .serial = "N/A",
            .firmware_version = "1.0",
            .supports_dma = false, // Current implementation is PIO only
            .current_speed = 0, // Unknown
        };
    }

    fn ideMediaChanged(dev: *BlockDevice) bool {
        const self: *Self = @fieldParentPtr("base", dev);

        // Only relevant for removable media (ATAPI)
        if (!self.drive_info.removable) {
            return false;
        }

        // TODO: Implement media change detection for ATAPI
        // This would involve checking the UNIT ATTENTION sense key
        return false;
    }

    fn ideRevalidate(dev: *BlockDevice) block.Error!void {
        const self: *Self = @fieldParentPtr("base", dev);

        // Re-read drive capacity (useful for removable media)
        const new_capacity = ide.getDriveCapacity(self.drive_index) catch |err| {
            return switch (err) {
                error.InvalidDrive => block.Error.DeviceNotFound,
                error.NoMedia => block.Error.MediaNotPresent,
                else => block.Error.IoError,
            };
        };

        // Update device parameters
        dev.block_size = new_capacity.sector_size;
        dev.total_blocks = new_capacity.sectors;

        logger.info("Revalidated {s}: {} blocks of {} bytes", .{
            dev.getName(),
            dev.total_blocks,
            dev.block_size,
        });
    }
};

// === PARTITION SUPPORT ===

pub const Partition = struct {
    base: BlockDevice,
    parent: *BlockDevice,
    start_block: u64,
    partition_number: u8,

    const partition_ops = BlockDevice.Operations{
        .read = partitionRead,
        .write = partitionWrite,
        .flush = partitionFlush,
        .trim = null,
        .get_info = null,
        .media_changed = null,
        .revalidate = null,
    };

    const Self = @This();

    pub fn create(
        parent: *BlockDevice,
        partition_number: u8,
        start_block: u64,
        block_count: u64,
    ) !*Self {
        const partition = try allocator.create(Self);
        errdefer allocator.destroy(partition);

        // Generate partition name
        var name: [16]u8 = [_]u8{0} ** 16;
        const parent_name = parent.getName();
        const str = try std.fmt.bufPrint(&name, "{s}p{}", .{ parent_name, partition_number });
        name[str.len] = 0;

        partition.* = .{
            .base = .{
                .name = name,
                .device_type = parent.device_type,
                .block_size = parent.block_size,
                .total_blocks = block_count,
                .max_transfer = parent.max_transfer,
                .features = parent.features,
                .ops = &partition_ops,
                .private_data = partition,
                .cache_policy = parent.cache_policy,
            },
            .parent = parent,
            .start_block = start_block,
            .partition_number = partition_number,
        };

        return partition;
    }

    pub fn destroy(self: *Self) void {
        allocator.destroy(self);
    }

    fn partitionRead(dev: *BlockDevice, start_block: u64, count: u32, buffer: []u8) block.Error!void {
        const self: Self = @fieldParentPtr("base", dev);
        return self.parent.read(self.start_block + start_block, count, buffer);
    }

    fn partitionWrite(dev: *BlockDevice, start_block: u64, count: u32, buffer: []const u8) block.Error!void {
        const self: Self = @fieldParentPtr("base", dev);
        return self.parent.write(self.start_block + start_block, count, buffer);
    }

    fn partitionFlush(dev: *BlockDevice) block.Error!void {
        const self: Self = @fieldParentPtr("base", dev);
        return self.parent.flush();
    }
};

// === INITIALIZATION ===

var ide_devices: std.ArrayList(*IDEBlockDevice) = undefined;

pub fn init() !void {
    ide_devices = std.ArrayList(*IDEBlockDevice).init(allocator);
    errdefer ide_devices.deinit();

    const manager = block.getManager();
    const drive_count = ide.getDriveCount();

    logger.info("Registering {} IDE drives as block devices", .{drive_count});

    for (0..drive_count) |i| {
        const ide_device = IDEBlockDevice.create(i) catch |err| {
            logger.err("Failed to create block device for drive {}: {}", .{ i, err });
            continue;
        };

        try ide_devices.append(ide_device);
        try manager.register(&ide_device.base);

        logger.info("Registered IDE drive {} as {s}", .{ i, ide_device.base.getName() });

        // TODO: Detect and create partitions here
        // This would involve reading the MBR/GPT and creating Partition devices
    }
}

pub fn deinit() void {
    const manager = block.getManager();

    for (ide_devices.items) |device| {
        manager.unregister(device.base.getName()) catch {};
        device.destroy();
    }

    ide_devices.deinit();
}
