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
const logger = std.log.scoped(.ide_block);

const allocator = @import("../memory.zig").bigAlloc.allocator();

pub const IDEBlockDevice = struct {
    base: BlockDevice,
    drive_index: usize,
    drive_info: ide.DriveInfo,
    physical_block_size: u32, // Actual hardware block size (512 for ATA, 2048 for ATAPI)
    physical_to_logical_shift: u5, // How many logical blocks per physical block (as shift)
    temp_buffer: []align(16) u8, // Buffer for partial physical block operations

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

        // Calculate the shift value for conversion
        const physical_block_size = drive_info.capacity.sector_size;
        const shift = calculateShift(physical_block_size);

        // Calculate total logical blocks (512-byte blocks)
        const logical_blocks_per_physical = physical_block_size / STANDARD_BLOCK_SIZE;
        const total_logical_blocks = drive_info.capacity.sectors * logical_blocks_per_physical;

        // Allocate temp buffer for partial block operations
        const temp_buffer = try allocator.alignedAlloc(u8, 16, physical_block_size);
        errdefer allocator.free(temp_buffer);

        device.* = .{
            .base = .{
                .name = device_name,
                .device_type = device_type,
                // .block_size = STANDARD_BLOCK_SIZE, // Always 512 bytes
                .total_blocks = total_logical_blocks,
                .max_transfer = if (drive_info.drive_type == .ATA)
                    256 * logical_blocks_per_physical // Convert physical limit to logical blocks
                else
                    65535 * logical_blocks_per_physical,
                .features = features,
                .ops = &ide_ops,
                .private_data = device,
                .cache_policy = cache_policy,
            },
            .drive_index = drive_index,
            .drive_info = drive_info,
            .physical_block_size = physical_block_size,
            .physical_to_logical_shift = shift,
            .temp_buffer = temp_buffer,
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
        allocator.free(self.temp_buffer);
        allocator.destroy(self);
    }

    fn calculateShift(physical_block_size: u32) u5 {
        // Calculate how many times to shift to convert between block sizes
        // 512 -> 0, 1024 -> 1, 2048 -> 2, 4096 -> 3
        var size = physical_block_size / STANDARD_BLOCK_SIZE;
        var shift: u5 = 0;
        while (size > 1) : (shift += 1) {
            size >>= 1;
        }
        return shift;
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

    fn ideRead(dev: *BlockDevice, start_block: u32, count: u32, buffer: []u8) BlockError!void {
        const self: *Self = @fieldParentPtr("base", dev);

        // If physical block size equals logical block size, direct operation
        if (self.physical_block_size == STANDARD_BLOCK_SIZE) {
            return ideReadDirect(self, start_block, count, buffer);
        }

        // Otherwise, need to handle block size translation
        return ideReadWithTranslation(self, start_block, count, buffer);
    }

    fn ideReadDirect(self: *Self, start_block: u32, count: u32, buffer: []u8) BlockError!void {
        // Direct 1:1 mapping for ATA drives with 512-byte sectors
        var op = ide.IDEOperation{
            .drive_idx = self.drive_index,
            .lba = @truncate(start_block),
            .count = @truncate(count),
            .buffer = .{ .read = buffer },
            .is_write = false,
        };

        ide.performOperation(&op) catch |err| {
            self.base.stats.errors += 1;
            return mapIDEError(err);
        };
    }

    fn ideReadWithTranslation(self: *Self, start_logical: u32, count: u32, buffer: []u8) BlockError!void {
        const logical_per_physical = @as(u32, 1) << self.physical_to_logical_shift;

        // Calculate physical block range
        const first_physical = start_logical >> self.physical_to_logical_shift;
        const last_logical = start_logical + count - 1;
        const last_physical = last_logical >> self.physical_to_logical_shift;
        const physical_count = last_physical - first_physical + 1;

        // Calculate offsets within first and last physical blocks
        const first_offset = (start_logical & (logical_per_physical - 1)) * STANDARD_BLOCK_SIZE;
        const last_end = ((last_logical & (logical_per_physical - 1)) + 1) * STANDARD_BLOCK_SIZE;

        var buffer_offset: usize = 0;

        // Handle first physical block (may be partial)
        if (first_offset != 0 or (physical_count == 1 and last_end != self.physical_block_size)) {
            // Need to read full physical block and extract relevant portion
            var op = ide.IDEOperation{
                .drive_idx = self.drive_index,
                .lba = @truncate(first_physical),
                .count = 1,
                .buffer = .{ .read = self.temp_buffer },
                .is_write = false,
            };

            ide.performOperation(&op) catch |err| {
                self.base.stats.errors += 1;
                return mapIDEError(err);
            };

            // Copy relevant portion to output buffer
            const copy_start = first_offset;
            const copy_end = if (physical_count == 1) last_end else self.physical_block_size;
            const copy_len = copy_end - copy_start;
            @memcpy(buffer[0..copy_len], self.temp_buffer[copy_start..copy_end]);
            buffer_offset += copy_len;

            if (physical_count == 1) return;
        }

        // Handle middle physical blocks (all complete)
        const middle_start = if (first_offset == 0) first_physical else first_physical + 1;
        const middle_count = if (last_end == self.physical_block_size)
            physical_count - @intFromBool(first_offset != 0)
        else
            physical_count - @intFromBool(first_offset != 0) - 1;

        if (middle_count > 0) {
            var op = ide.IDEOperation{
                .drive_idx = self.drive_index,
                .lba = @truncate(middle_start),
                .count = @truncate(middle_count),
                .buffer = .{
                    .read = buffer[buffer_offset .. buffer_offset + middle_count * self.physical_block_size],
                },
                .is_write = false,
            };

            ide.performOperation(&op) catch |err| {
                self.base.stats.errors += 1;
                return mapIDEError(err);
            };

            buffer_offset += middle_count * self.physical_block_size;
        }

        // Handle last physical block (may be partial)
        if (physical_count > 1 and last_end != self.physical_block_size and first_offset == 0) {
            var op = ide.IDEOperation{
                .drive_idx = self.drive_index,
                .lba = @truncate(last_physical),
                .count = 1,
                .buffer = .{ .read = self.temp_buffer },
                .is_write = false,
            };

            ide.performOperation(&op) catch |err| {
                self.base.stats.errors += 1;
                return mapIDEError(err);
            };

            @memcpy(buffer[buffer_offset .. buffer_offset + last_end], self.temp_buffer[0..last_end]);
        }
    }

    fn ideWrite(dev: *BlockDevice, start_block: u32, count: u32, buffer: []const u8) BlockError!void {
        const self: *Self = @fieldParentPtr("base", dev);

        if (self.drive_info.drive_type != .ATA) {
            return BlockError.WriteProtected;
        }

        // If physical block size equals logical block size, direct operation
        if (self.physical_block_size == STANDARD_BLOCK_SIZE) {
            return ideWriteDirect(self, start_block, count, buffer);
        }

        // Otherwise, need to handle block size translation
        return ideWriteWithTranslation(self, start_block, count, buffer);
    }

    fn ideWriteDirect(self: *Self, start_block: u32, count: u32, buffer: []const u8) BlockError!void {
        var op = ide.IDEOperation{
            .drive_idx = self.drive_index,
            .lba = @truncate(start_block),
            .count = @truncate(count),
            .buffer = .{ .write = buffer },
            .is_write = true,
        };

        ide.performOperation(&op) catch |err| {
            self.base.stats.errors += 1;
            return mapIDEError(err);
        };
    }

    fn ideWriteWithTranslation(self: *Self, start_logical: u32, count: u32, buffer: []const u8) BlockError!void {
        const logical_per_physical = @as(u32, 1) << self.physical_to_logical_shift;

        // Calculate physical block range
        const first_physical = start_logical >> self.physical_to_logical_shift;
        const last_logical = start_logical + count - 1;
        const last_physical = last_logical >> self.physical_to_logical_shift;
        const physical_count = last_physical - first_physical + 1;

        // Calculate offsets within first and last physical blocks
        const first_offset = (start_logical & (logical_per_physical - 1)) * STANDARD_BLOCK_SIZE;
        const last_end = ((last_logical & (logical_per_physical - 1)) + 1) * STANDARD_BLOCK_SIZE;

        var buffer_offset: usize = 0;

        // Handle first physical block (may need read-modify-write)
        if (first_offset != 0 or (physical_count == 1 and last_end != self.physical_block_size)) {
            // Read existing block
            var read_op = ide.IDEOperation{
                .drive_idx = self.drive_index,
                .lba = @truncate(first_physical),
                .count = 1,
                .buffer = .{ .read = self.temp_buffer },
                .is_write = false,
            };

            ide.performOperation(&read_op) catch |err| {
                self.base.stats.errors += 1;
                return mapIDEError(err);
            };

            // Modify relevant portion
            const copy_start = first_offset;
            const copy_end = if (physical_count == 1) last_end else self.physical_block_size;
            const copy_len = copy_end - copy_start;
            @memcpy(self.temp_buffer[copy_start..copy_end], buffer[0..copy_len]);
            buffer_offset += copy_len;

            // Write back modified block
            var write_op = ide.IDEOperation{
                .drive_idx = self.drive_index,
                .lba = @truncate(first_physical),
                .count = 1,
                .buffer = .{ .write = self.temp_buffer },
                .is_write = true,
            };

            ide.performOperation(&write_op) catch |err| {
                self.base.stats.errors += 1;
                return mapIDEError(err);
            };

            if (physical_count == 1) return;
        }

        // Handle middle physical blocks (all complete)
        const middle_start = if (first_offset == 0) first_physical else first_physical + 1;
        const middle_count = if (last_end == self.physical_block_size)
            physical_count - @intFromBool(first_offset != 0)
        else
            physical_count - @intFromBool(first_offset != 0) - 1;

        if (middle_count > 0) {
            var op = ide.IDEOperation{
                .drive_idx = self.drive_index,
                .lba = @truncate(middle_start),
                .count = @truncate(middle_count),
                .buffer = .{
                    .write = buffer[buffer_offset .. buffer_offset + middle_count * self.physical_block_size],
                },
                .is_write = true,
            };

            ide.performOperation(&op) catch |err| {
                self.base.stats.errors += 1;
                return mapIDEError(err);
            };

            buffer_offset += middle_count * self.physical_block_size;
        }

        // Handle last physical block (may need read-modify-write)
        if (physical_count > 1 and last_end != self.physical_block_size and first_offset == 0) {
            // Read existing block
            var read_op = ide.IDEOperation{
                .drive_idx = self.drive_index,
                .lba = @truncate(last_physical),
                .count = 1,
                .buffer = .{ .read = self.temp_buffer },
                .is_write = false,
            };

            ide.performOperation(&read_op) catch |err| {
                self.base.stats.errors += 1;
                return mapIDEError(err);
            };

            // Modify relevant portion
            @memcpy(self.temp_buffer[0..last_end], buffer[buffer_offset .. buffer_offset + last_end]);

            // Write back modified block
            var write_op = ide.IDEOperation{
                .drive_idx = self.drive_index,
                .lba = @truncate(last_physical),
                .count = 1,
                .buffer = .{ .write = self.temp_buffer },
                .is_write = true,
            };

            ide.performOperation(&write_op) catch |err| {
                self.base.stats.errors += 1;
                return mapIDEError(err);
            };
        }
    }

    fn ideFlush(dev: *BlockDevice) BlockError!void {
        const self: *Self = @fieldParentPtr("base", dev);

        if (self.drive_info.drive_type != .ATA) {
            return;
        }

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
            .physical_block_size = self.physical_block_size,
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

        // Recalculate logical blocks
        const logical_blocks_per_physical = new_info.capacity.sector_size / STANDARD_BLOCK_SIZE;
        dev.total_blocks = new_info.capacity.sectors * logical_blocks_per_physical;

        self.drive_info = new_info;
        self.physical_block_size = new_info.capacity.sector_size;
        self.physical_to_logical_shift = calculateShift(new_info.capacity.sector_size);

        // Reallocate temp buffer if size changed
        if (self.temp_buffer.len != self.physical_block_size) {
            allocator.free(self.temp_buffer);
            self.temp_buffer = allocator.alignedAlloc(u8, 16, self.physical_block_size) catch {
                return BlockError.OutOfMemory;
            };
        }

        logger.info("Revalidated {s}: {} logical blocks ({} physical blocks of {} bytes)", .{
            dev.getName(),
            dev.total_blocks,
            new_info.capacity.sectors,
            self.physical_block_size,
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
