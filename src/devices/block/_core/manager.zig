const std = @import("std");
const logger = std.log.scoped(.@"blockdev(manager)");
const ArrayList = std.ArrayList;

const core = @import("../core.zig");
const Disk = core.Disk;
const CD = core.CD;
const Ram = core.Ram;

const types = core.types;
const BlockDevice = core.BlockDevice;
const BlockProvider = core.BlockProvider;
const BlockError = types.BlockError;
const DeviceSource = types.DeviceSource;
const RegisteredDevice = types.RegisteredDevice;

const Mutex = @import("../../../task/semaphore.zig").Mutex;
const allocator = @import("../../../memory.zig").smallAlloc.allocator();

const List = ArrayList(RegisteredDevice);

var devices = std.StringHashMap(RegisteredDevice).init(allocator);
var providers = std.EnumArray(DeviceSource, ?*BlockProvider).initFill(null);

var mutex = Mutex{};

const Self = @This();

/// Register a provider for a device type
pub fn registerProvider(source: DeviceSource, provider: *BlockProvider) !void {
    mutex.acquire();
    defer mutex.release();

    if (providers.get(source) != null) return BlockError.AlreadyExists;

    providers.set(source, provider);
    logger.info("{s} provider registered", .{@tagName(source)});
}

/// Register a device
pub fn registerDevice(
    device: *BlockDevice,
    source: DeviceSource,
    auto_discovered: bool,
) !*RegisteredDevice {
    mutex.acquire();
    defer mutex.release();

    if (devices.contains(device.getName())) {
        return BlockError.AlreadyExists;
    }

    // Save parameters if provided
    const registered = try devices.getOrPut(device.getName());
    registered.value_ptr.* = .{
        .allocator = allocator,
        .device = device,
        .source = source,
        .auto_discovered = auto_discovered,
    };

    logger.info("registered {s} ({s}: {} blocks of {} bytes)", .{
        device.getName(),
        @tagName(source),
        device.total_blocks,
        device.block_size,
    });

    return registered.value_ptr;
}

/// Create a custom device
pub fn createDevice(source: DeviceSource, params: *const void) !*RegisteredDevice {
    const provider = providers.get(source) orelse {
        logger.err("no provider for {s}", .{@tagName(source)});
        return BlockError.NotSupported;
    };

    // const device = try provider.vtable.create(provider.context, params);
    // errdefer provider.vtable.deinit(provider.context);
    const device = try provider.create(params);
    errdefer provider.destroy(device.minor);

    return try registerDevice(device, source, false);
}

pub fn removeDevice(name: []const u8) !void {
    mutex.acquire();
    defer mutex.release();

    const entry = devices.getEntry(name) orelse {
        return BlockError.DeviceNotFound;
    };
    const key = entry.key_ptr;
    const registered = entry.value_ptr;

    if (registered.auto_discovered and registered.source == .DISK) {
        return BlockError.NotSupported; // No removal of physical disks
    }

    const provider = providers.get(registered.source) orelse {
        logger.err("no provider for {s}", .{@tagName(registered.source)});
        return BlockError.NotSupported;
    };

    provider.destroy(registered.device.minor);

    // Remove from the map
    devices.removeByPtr(key);
    logger.info("{s} device removed", .{name});
}

/// Find a device by name
pub fn find(name: []const u8) ?*BlockDevice {
    mutex.acquire();
    defer mutex.release();

    for (devices.items) |device| {
        if (std.mem.eql(u8, device.device.getName(), name)) {
            return device.device;
        }
    }
    return null;
}

/// Get the number of devices
pub fn count() usize {
    mutex.acquire();
    defer mutex.release();

    // return devices.items.len;
    return devices.count();
}

pub fn iterator() std.StringHashMap(RegisteredDevice).Iterator {
    return devices.iterator();
}

/// Get global statistics
pub fn getGlobalStats() struct {
    total_reads: u64,
    total_writes: u64,
    total_errors: u64,
    total_capacity_mb: u64,
} {
    mutex.acquire();
    defer mutex.release();

    var stats = .{
        .total_reads = @as(u64, 0),
        .total_writes = @as(u64, 0),
        .total_errors = @as(u64, 0),
        .total_capacity_mb = @as(u64, 0),
    };

    var it = devices.iterator();
    while (it.next()) |entry| {
        const device = entry.value_ptr.device;
        stats.total_reads += device.stats.reads_completed;
        stats.total_writes += device.stats.writes_completed;
        stats.total_errors += device.stats.errors;
        stats.total_capacity_mb += (device.total_blocks * device.block_size) / (1024 * 1024);
    }

    return stats;
}

/// Clean up a device according to its type
fn cleanupDevice(reg_device: *RegisteredDevice) void {

    // Call the appropriate cleanup method according to the type
    switch (reg_device.source) {
        .DISK => {
            const disk_device: *Disk = @fieldParentPtr("base", reg_device.device);
            disk_device.destroy();
        },
        .CDROM => {
            const cdrom_device: *CD = @fieldParentPtr("base", reg_device.device);
            cdrom_device.destroy();
        },
        .RAM => {
            const ram_device: *Ram = @fieldParentPtr("base", reg_device.device);
            ram_device.destroy();
        },
        else => {
            logger.warn("No cleanup for device type: {s}", .{@tagName(reg_device.source)});
        },
    }
}

pub fn deinit() void {
    for (devices.items) |*device| {
        cleanupDevice(device);
        device.deinit();
    }
    devices.deinit();

    var iter = providers.iterator();
    while (iter.next()) |entry| {
        if (entry.value.*) |provider| {
            provider.deinit();
        }
    }
}
