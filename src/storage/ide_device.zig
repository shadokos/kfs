const std = @import("std");
const ide = @import("../drivers/ide/ide.zig");
const BlockDevice = @import("block_device.zig").BlockDevice;
const BlockError = @import("block_device.zig").BlockError;
const DeviceType = @import("block_device.zig").DeviceType;
const Features = @import("block_device.zig").Features;
const CachePolicy = @import("block_device.zig").CachePolicy;
const DeviceInfo = @import("block_device.zig").DeviceInfo;
const Operations = @import("block_device.zig").Operations;
const STANDARD_BLOCK_SIZE = @import("block_device.zig").STANDARD_BLOCK_SIZE;
const BlockTranslator = @import("translator.zig").BlockTranslator;
const createTranslator = @import("translator.zig").createTranslator;
const logger = std.log.scoped(.ide_block);

const allocator = @import("../memory.zig").bigAlloc.allocator();

pub const IDEBlockDevice = struct {
    base: BlockDevice,
    drive_index: usize,
    drive_info: ide.DriveInfo,

    const ide_ops = Operations{
        .physical_io = idePhysicalIO,
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

        // Create appropriate translator based on physical block size
        const physical_block_size = drive_info.capacity.sector_size;
        const translator = try createTranslator(physical_block_size);
        errdefer translator.deinit();

        // Calculate total logical blocks (512-byte blocks)
        const logical_blocks_per_physical = physical_block_size / STANDARD_BLOCK_SIZE;
        const total_logical_blocks = drive_info.capacity.sectors * logical_blocks_per_physical;

        device.* = .{
            .base = .{
                .name = device_name,
                .device_type = device_type,
                .block_size = STANDARD_BLOCK_SIZE, // Always 512 bytes for logical interface
                .total_blocks = total_logical_blocks,
                .max_transfer = if (drive_info.drive_type == .ATA)
                    256 * logical_blocks_per_physical // Convert physical limit to logical blocks
                else
                    65535 * logical_blocks_per_physical,
                .features = features,
                .ops = &ide_ops,
                .translator = translator,
                .private_data = device,
                .cache_policy = cache_policy,
            },
            .drive_index = drive_index,
            .drive_info = drive_info,
        };

        logger.info("Created IDE device {s}: {} logical blocks ({} physical blocks of {} bytes)", .{
            device.base.getName(),
            total_logical_blocks,
            drive_info.capacity.sectors,
            physical_block_size,
        });

        return device;
    }

    pub fn destroy(self: *Self) void {
        self.base.deinit(); // This will clean up the translator
        allocator.destroy(self);
    }

    fn generateDeviceName(drive_index: usize, drive_info: ide.DriveInfo) ![16]u8 {
        var name: [16]u8 = [_]u8{0} ** 16;

        // Count devices of the same type that have lower indices
        var type_index: usize = 0;
        for (0..drive_index) |i| {
            if (ide.getDriveInfo(i)) |info| {
                if (info.drive_type == drive_info.drive_type) {
                    type_index += 1;
                }
            }
        }

        if (drive_info.drive_type == .ATAPI) {
            const str = try std.fmt.bufPrint(&name, "cd{}", .{type_index});
            name[str.len] = 0;
        } else {
            const letter: u8 = @truncate('a' + type_index);
            const str = try std.fmt.bufPrint(&name, "hd{c}", .{letter});
            name[str.len] = 0;
        }

        return name;
    }

    /// Physical I/O function - this is where actual IDE operations happen
    fn idePhysicalIO(
        context: *anyopaque,
        physical_block: u32,
        count: u32,
        buffer: []u8,
        is_write: bool,
    ) BlockError!void {
        // Get the IDE device from the context (which is the BlockDevice)
        const block_device: *BlockDevice = @ptrCast(@alignCast(context));
        const self: *Self = @fieldParentPtr("base", block_device);

        // Validate operation
        if (is_write and self.drive_info.drive_type != .ATA) {
            return BlockError.WriteProtected;
        }

        // Calculate expected buffer size
        const expected_size = count * self.base.translator.physical_block_size;
        if (buffer.len < expected_size) {
            return BlockError.BufferTooSmall;
        }

        // Perform IDE operation
        var op = ide.IDEOperation{
            .drive_idx = self.drive_index,
            .lba = @truncate(physical_block),
            .count = @truncate(count),
            .buffer = if (is_write)
                .{ .write = buffer[0..expected_size] }
            else
                .{ .read = buffer[0..expected_size] },
            .is_write = is_write,
        };

        ide.performOperation(&op) catch |err| {
            return mapIDEError(err);
        };
    }

    fn ideFlush(dev: *BlockDevice) BlockError!void {
        const self: *Self = @fieldParentPtr("base", dev);

        if (self.drive_info.drive_type != .ATA) {
            return;
        }

        // IDE flush cache command
        var flush_buffer: [STANDARD_BLOCK_SIZE]u8 = undefined;
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
            .physical_block_size = self.drive_info.capacity.sector_size,
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

        // Check if physical block size changed
        if (new_info.capacity.sector_size != self.drive_info.capacity.sector_size) {
            // Need to recreate translator
            self.base.translator.deinit();
            self.base.translator = createTranslator(new_info.capacity.sector_size) catch {
                return BlockError.OutOfMemory;
            };
        }

        // Recalculate logical blocks
        const logical_blocks_per_physical = new_info.capacity.sector_size / STANDARD_BLOCK_SIZE;
        dev.total_blocks = new_info.capacity.sectors * logical_blocks_per_physical;

        // Update max transfer
        dev.max_transfer = if (new_info.drive_type == .ATA)
            256 * logical_blocks_per_physical
        else
            65535 * logical_blocks_per_physical;

        self.drive_info = new_info;

        logger.info("Revalidated {s}: {} logical blocks ({} physical blocks of {} bytes)", .{
            dev.getName(),
            dev.total_blocks,
            new_info.capacity.sectors,
            new_info.capacity.sector_size,
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
