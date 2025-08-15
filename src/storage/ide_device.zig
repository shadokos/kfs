const std = @import("std");
const ide = @import("../drivers/ide/ide.zig");
const BlockDevice = @import("block_device.zig").BlockDevice;
const BlockError = @import("block_device.zig").BlockError;
const DeviceType = @import("block_device.zig").DeviceType;
const Features = @import("block_device.zig").Features;
const CachePolicy = @import("block_device.zig").CachePolicy;
const DeviceInfo = @import("block_device.zig").DeviceInfo;
const Operations = @import("block_device.zig").Operations;
const logger = std.log.scoped(.ide_block);

const allocator = @import("../memory.zig").smallAlloc.allocator();

pub const IDEBlockDevice = struct {
    base: BlockDevice,
    drive_index: usize,
    drive_info: ide.DriveInfo,

    const ide_ops = Operations{
        .read = ideRead,
        .write = ideWrite,
        .flush = ideFlush,
        .trim = null,
        .get_info = ideGetInfo,
        .media_changed = ideMediaChanged,
        .revalidate = ideRevalidate,
    };

    const Self = @This();

    pub fn create(drive_index: usize) !*Self {
        const drive_info = ide.getDriveInfo(drive_index) orelse return error.InvalidDrive;

        const device = try allocator.create(Self);
        errdefer allocator.destroy(device);

        const device_name = try generateDeviceName(drive_index, drive_info);

        const device_type: DeviceType = switch (drive_info.drive_type) {
            .ATA => .HardDisk,
            .ATAPI => .CDROM,
            else => .Unknown,
        };

        const features = Features{
            .readable = true,
            .writable = drive_info.drive_type == .ATA,
            .removable = drive_info.removable,
            .supports_flush = drive_info.drive_type == .ATA,
            .supports_trim = false,
            .supports_barriers = false,
        };

        const cache_policy: CachePolicy = if (drive_info.drive_type == .ATAPI)
            .NoCache
        else
            .WriteBack;

        device.* = .{
            .base = .{
                .name = device_name,
                .device_type = device_type,
                .block_size = drive_info.capacity.sector_size,
                .total_blocks = drive_info.capacity.sectors,
                .max_transfer = if (drive_info.drive_type == .ATA) 256 else 65535,
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

    fn generateDeviceName(drive_index: usize, drive_info: ide.DriveInfo) ![16]u8 {
        var name: [16]u8 = [_]u8{0} ** 16;

        if (drive_info.drive_type == .ATAPI) {
            const str = try std.fmt.bufPrint(&name, "cd{}", .{drive_index});
            name[str.len] = 0;
        } else {
            const letter: u8 = @truncate('a' + drive_index);
            const str = try std.fmt.bufPrint(&name, "hd{c}", .{letter});
            name[str.len] = 0;
        }

        return name;
    }

    fn ideRead(dev: *BlockDevice, start_block: u64, count: u32, buffer: []u8) BlockError!void {
        const self: *Self = @fieldParentPtr("base", dev);

        if (self.drive_info.drive_type == .ATAPI) {
            const sectors_per_block = dev.block_size / 2048;
            if (sectors_per_block == 0) return BlockError.InvalidOperation;

            const actual_count = count * sectors_per_block;
            if (actual_count > 65535) return BlockError.OutOfBounds;
        }

        var op = ide.IDEOperation{
            .drive_idx = self.drive_index,
            .lba = start_block,
            .count = @truncate(count),
            .buffer = .{ .read = buffer },
            .is_write = false,
        };

        ide.performOperation(&op) catch |err| {
            dev.stats.errors += 1;
            return mapIDEError(err);
        };
    }

    fn ideWrite(dev: *BlockDevice, start_block: u64, count: u32, buffer: []const u8) BlockError!void {
        const self: *Self = @fieldParentPtr("base", dev);

        if (self.drive_info.drive_type != .ATA) {
            return BlockError.WriteProtected;
        }

        var op = ide.IDEOperation{
            .drive_idx = self.drive_index,
            .lba = start_block,
            .count = @truncate(count),
            .buffer = .{ .write = buffer },
            .is_write = true,
        };

        ide.performOperation(&op) catch |err| {
            dev.stats.errors += 1;
            return mapIDEError(err);
        };
    }

    fn ideFlush(dev: *BlockDevice) BlockError!void {
        const self: *Self = @fieldParentPtr("base", dev);

        if (self.drive_info.drive_type != .ATA) {
            return;
        }

        var flush_buffer: [512]u8 = undefined;
        var op = ide.IDEOperation{
            .drive_idx = self.drive_index,
            .lba = 0,
            .count = 0,
            .buffer = .{ .write = &flush_buffer },
            .is_write = true,
        };

        ide.performOperation(&op) catch |err| {
            return mapIDEError(err);
        };
    }

    fn ideGetInfo(dev: *BlockDevice) DeviceInfo {
        const self: *Self = @fieldParentPtr("base", dev);

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
            .supports_dma = false,
            .current_speed = 0,
        };
    }

    fn ideMediaChanged(dev: *BlockDevice) bool {
        const self: *Self = @fieldParentPtr("base", dev);

        if (!self.drive_info.removable) {
            return false;
        }

        return false;
    }

    fn ideRevalidate(dev: *BlockDevice) BlockError!void {
        const self: *Self = @fieldParentPtr("base", dev);

        const new_info = ide.getDriveInfo(self.drive_index) orelse return BlockError.DeviceNotFound;

        dev.block_size = new_info.capacity.sector_size;
        dev.total_blocks = new_info.capacity.sectors;
        self.drive_info = new_info;

        logger.info("Revalidated {s}: {} blocks of {} bytes", .{
            dev.getName(),
            dev.total_blocks,
            dev.block_size,
        });
    }

    fn mapIDEError(err: ide.IDEError) BlockError {
        return switch (err) {
            ide.IDEError.InvalidDrive => BlockError.DeviceNotFound,
            ide.IDEError.BufferTooSmall => BlockError.BufferTooSmall,
            ide.IDEError.OutOfBounds => BlockError.OutOfBounds,
            ide.IDEError.Timeout => BlockError.IoError,
            ide.IDEError.NoMedia => BlockError.MediaNotPresent,
            ide.IDEError.NotSupported => BlockError.NotSupported,
            ide.IDEError.MediaChanged => BlockError.MediaNotPresent,
            else => BlockError.IoError,
        };
    }
};

pub const Partition = struct {
    base: BlockDevice,
    parent: *BlockDevice,
    start_block: u64,
    partition_number: u8,

    const partition_ops = Operations{
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

    fn partitionRead(dev: *BlockDevice, start_block: u64, count: u32, buffer: []u8) BlockError!void {
        const self: *Self = @fieldParentPtr("base", dev);
        return self.parent.read(self.start_block + start_block, count, buffer);
    }

    fn partitionWrite(dev: *BlockDevice, start_block: u64, count: u32, buffer: []const u8) BlockError!void {
        const self: *Self = @fieldParentPtr("base", dev);
        return self.parent.write(self.start_block + start_block, count, buffer);
    }

    fn partitionFlush(dev: *BlockDevice) BlockError!void {
        const self: *Self = @fieldParentPtr("base", dev);
        return self.parent.flush();
    }
};