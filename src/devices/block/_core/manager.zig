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

devices: ArrayList(RegisteredDevice),
providers: std.EnumArray(DeviceSource, ?*BlockProvider),
mutex: Mutex = .{},
next_device_id: u32 = 0,

const Self = @This();

pub fn init() Self {
    return .{
        .devices = ArrayList(RegisteredDevice).init(allocator),
        .providers = std.EnumArray(DeviceSource, ?*BlockProvider).initFill(null),
    };
}

pub fn deinit(self: *Self) void {
    // Nettoyer tous les dispositifs
    for (self.devices.items) |*device| {
        self.cleanupDevice(device);
        device.deinit();
    }
    self.devices.deinit();

    // Nettoyer les providers
    var iter = self.providers.iterator();
    while (iter.next()) |entry| {
        if (entry.value.*) |provider| {
            provider.deinit();
        }
    }
}

/// Enregistrer un provider pour un type de dispositif
pub fn registerProvider(self: *Self, source: DeviceSource, provider: *BlockProvider) !void {
    self.mutex.acquire();
    defer self.mutex.release();

    if (self.providers.get(source) != null) return BlockError.AlreadyExists;

    self.providers.set(source, provider);
    logger.info("{s} provider registered", .{@tagName(source)});
}

/// Enregistrer un dispositif
pub fn registerDevice(
    self: *Self,
    device: *BlockDevice,
    source: DeviceSource,
    auto_discovered: bool,
    params: ?[]const u8,
) !*RegisteredDevice {
    self.mutex.acquire();
    defer self.mutex.release();

    // Vérifier l'unicité du nom
    for (self.devices.items) |existing| {
        if (std.mem.eql(u8, existing.device.getName(), device.getName())) {
            return BlockError.AlreadyExists;
        }
    }

    // Sauvegarder les paramètres si fournis
    const saved_params = if (params) |p| try allocator.dupe(u8, p) else null;

    const registered = try self.devices.addOne();
    registered.* = .{
        .allocator = allocator,
        .device = device,
        .source = source,
        .auto_discovered = auto_discovered,
        .creation_params = saved_params,
    };

    logger.info("registered {s} ({s}: {} blocks of {} bytes)", .{
        device.getName(),
        @tagName(source),
        device.total_blocks,
        device.block_size,
    });

    return registered;
}

/// Créer un dispositif personnalisé
pub fn createDevice(self: *Self, source: DeviceSource, params: *const void) !*RegisteredDevice {
    const provider = self.providers.get(source) orelse {
        logger.err("no provider for {s}", .{@tagName(source)});
        return BlockError.NotSupported;
    };

    const device = try provider.vtable.create(provider.context, params);
    errdefer provider.vtable.deinit(provider.context);
    return try self.registerDevice(device, source, false, null);
}

/// Supprimer un dispositif
pub fn removeDevice(self: *Self, name: []const u8) !void {
    self.mutex.acquire();
    defer self.mutex.release();

    for (self.devices.items, 0..) |*reg_device, i| {
        if (std.mem.eql(u8, reg_device.device.getName(), name)) {
            if (reg_device.auto_discovered and reg_device.source == .DISK) {
                return BlockError.NotSupported; // Pas de suppression des disques physiques
            }

            self.cleanupDevice(reg_device);
            reg_device.deinit();
            _ = self.devices.swapRemove(i);

            logger.info("{s} device removed", .{name});
            return;
        }
    }

    return BlockError.DeviceNotFound;
}

/// Trouver un dispositif par nom
pub fn find(self: *Self, name: []const u8) ?*BlockDevice {
    self.mutex.acquire();
    defer self.mutex.release();

    for (self.devices.items) |device| {
        if (std.mem.eql(u8, device.device.getName(), name)) {
            return device.device;
        }
    }
    return null;
}

/// Obtenir un dispositif par index
pub fn getByIndex(self: *Self, index: usize) ?*BlockDevice {
    self.mutex.acquire();
    defer self.mutex.release();

    if (index >= self.devices.items.len) return null;
    return self.devices.items[index].device;
}

/// Obtenir le nombre de dispositifs
pub fn count(self: *Self) usize {
    self.mutex.acquire();
    defer self.mutex.release();

    return self.devices.items.len;
}

/// Obtenir des statistiques globales
pub fn getGlobalStats(self: *Self) struct {
    total_reads: u64,
    total_writes: u64,
    total_errors: u64,
    total_capacity_mb: u64,
} {
    self.mutex.acquire();
    defer self.mutex.release();

    var stats = .{
        .total_reads = @as(u64, 0),
        .total_writes = @as(u64, 0),
        .total_errors = @as(u64, 0),
        .total_capacity_mb = @as(u64, 0),
    };

    for (self.devices.items) |reg_device| {
        const device = reg_device.device;
        stats.total_reads += device.stats.reads_completed;
        stats.total_writes += device.stats.writes_completed;
        stats.total_errors += device.stats.errors;
        stats.total_capacity_mb += (device.total_blocks * device.block_size) / (1024 * 1024);
    }

    return stats;
}

/// Nettoyer un dispositif selon son type
fn cleanupDevice(self: *Self, reg_device: *RegisteredDevice) void {
    _ = self;

    // Appeler la méthode de nettoyage appropriée selon le type
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
