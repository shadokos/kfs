const std = @import("std");
const ArrayList = std.ArrayList;
const BlockDevice = @import("block_device.zig").BlockDevice;
const BlockError = @import("block_device.zig").BlockError;
const Mutex = @import("../task/semaphore.zig").Mutex;
const allocator = @import("../memory.zig").smallAlloc.allocator();
const logger = std.log.scoped(.device_manager);

pub const DeviceManager = struct {
    devices: ArrayList(*BlockDevice),
    mutex: Mutex = .{},
    next_device_id: u32 = 0,

    const Self = @This();

    pub fn init() Self {
        return .{
            .devices = ArrayList(*BlockDevice).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.devices.deinit();
    }

    pub fn register(self: *Self, device: *BlockDevice) !void {
        self.mutex.acquire();
        defer self.mutex.release();

        for (self.devices.items) |existing| {
            if (std.mem.eql(u8, existing.getName(), device.getName())) {
                return BlockError.DeviceExists;
            }
        }

        try self.devices.append(device);
        logger.info("Registered block device: {s} ({} blocks of {} bytes)", .{
            device.getName(),
            device.total_blocks,
            device.block_size,
        });
    }

    pub fn unregister(self: *Self, name: []const u8) !void {
        self.mutex.acquire();
        defer self.mutex.release();

        for (self.devices.items, 0..) |device, i| {
            if (std.mem.eql(u8, device.getName(), name)) {
                _ = self.devices.swapRemove(i);
                logger.info("Unregistered block device: {s}", .{name});
                return;
            }
        }
        return BlockError.DeviceNotFound;
    }

    pub fn find(self: *Self, name: []const u8) ?*BlockDevice {
        self.mutex.acquire();
        defer self.mutex.release();

        for (self.devices.items) |device| {
            if (std.mem.eql(u8, device.getName(), name)) {
                return device;
            }
        }
        return null;
    }

    pub fn list(self: *Self) void {
        self.mutex.acquire();
        defer self.mutex.release();

        logger.info("=== Block Devices ===", .{});
        for (self.devices.items) |device| {
            const size_mb = (device.total_blocks * device.block_size) / (1024 * 1024);
            logger.info("{s}: {s}, {} MB ({} x {} bytes)", .{
                device.getName(),
                @tagName(device.device_type),
                size_mb,
                device.total_blocks,
                device.block_size,
            });
            logger.info("  Features: R:{} W:{} Removable:{} Flush:{} Trim:{}", .{
                device.features.readable,
                device.features.writable,
                device.features.removable,
                device.features.supports_flush,
                device.features.supports_trim,
            });
            logger.info("  Stats: Reads:{} Writes:{} Errors:{}", .{
                device.stats.reads_completed,
                device.stats.writes_completed,
                device.stats.errors,
            });
        }
    }

    pub fn getDeviceByIndex(self: *Self, index: usize) ?*BlockDevice {
        self.mutex.acquire();
        defer self.mutex.release();

        if (index >= self.devices.items.len) return null;
        return self.devices.items[index];
    }

    pub fn getDeviceCount(self: *Self) usize {
        self.mutex.acquire();
        defer self.mutex.release();

        return self.devices.items.len;
    }
};