// src/storage/device_manager.zig
// Système unifié de gestion des dispositifs de stockage

const std = @import("std");
const ArrayList = std.ArrayList;
const BlockDevice = @import("block_device.zig").BlockDevice;
const BlockError = @import("block_device.zig").BlockError;
const Mutex = @import("../../task/semaphore.zig").Mutex;
const logger = std.log.scoped(.device_manager);
const allocator = @import("../../memory.zig").smallAlloc.allocator();

/// Type de source d'un dispositif
pub const DeviceSource = enum {
    IDE, // Découvert via contrôleur IDE
    RAM, // RAM disk créé manuellement
    Loop, // Loop device (futur)
    Network, // iSCSI, NBD, etc. (futur)
};

/// Informations sur un dispositif enregistré
pub const RegisteredDevice = struct {
    device: *BlockDevice,
    source: DeviceSource,
    auto_discovered: bool,
    creation_params: ?[]const u8 = null,

    pub fn deinit(self: *RegisteredDevice) void {
        if (self.creation_params) |params| {
            allocator.free(params);
        }
    }
};

/// Interface pour les fournisseurs de dispositifs
pub const DeviceProvider = struct {
    vtable: *const VTable,
    context: *anyopaque,

    pub const VTable = struct {
        /// Découverte automatique (retourne le nombre de devices trouvés)
        discover: *const fn (ctx: *anyopaque) u32,

        /// Créer un dispositif découvert
        createDiscovered: *const fn (ctx: *anyopaque, index: u32) anyerror!*BlockDevice,

        /// Créer un dispositif avec paramètres
        createCustom: ?*const fn (ctx: *anyopaque, params: []const u8) anyerror!*BlockDevice,

        /// Nettoyer les ressources du provider
        deinit: *const fn (ctx: *anyopaque) void,
    };

    pub fn discover(self: *DeviceProvider) u32 {
        return self.vtable.discover(self.context);
    }

    pub fn createDiscovered(self: *DeviceProvider, index: u32) !*BlockDevice {
        return self.vtable.createDiscovered(self.context, index);
    }

    pub fn createCustom(self: *DeviceProvider, params: []const u8) !*BlockDevice {
        if (self.vtable.createCustom) |create_fn| {
            return create_fn(self.context, params);
        }
        return BlockError.NotSupported;
    }

    pub fn deinit(self: *DeviceProvider) void {
        self.vtable.deinit(self.context);
    }
};

/// Gestionnaire unifié des dispositifs
pub const DeviceManager = struct {
    devices: ArrayList(RegisteredDevice),
    providers: std.EnumArray(DeviceSource, ?*DeviceProvider),
    mutex: Mutex = .{},
    next_device_id: u32 = 0,

    const Self = @This();

    pub fn init() Self {
        return .{
            .devices = ArrayList(RegisteredDevice).init(allocator),
            .providers = std.EnumArray(DeviceSource, ?*DeviceProvider).initFill(null),
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
    pub fn registerProvider(self: *Self, source: DeviceSource, provider: *DeviceProvider) !void {
        self.mutex.acquire();
        defer self.mutex.release();

        if (self.providers.get(source) != null) {
            return BlockError.DeviceExists;
        }

        self.providers.set(source, provider);
        logger.info("Registered provider for {s}", .{@tagName(source)});
    }

    /// Découverte automatique de tous les dispositifs
    pub fn discoverAll(self: *Self) !void {
        logger.info("=== Auto-discovering devices ===", .{});

        var iter = self.providers.iterator();
        while (iter.next()) |entry| {
            const source = entry.key;
            const provider = entry.value.* orelse continue;

            // get the number of devices discovered
            const n = provider.discover();
            logger.info("{s}: found {} devices", .{ @tagName(source), n });

            for (0..self.count()) |i| {
                const device = provider.createDiscovered(@truncate(i)) catch |err| {
                    logger.err("Failed to create {s} device {}: {}", .{ @tagName(source), i, err });
                    continue;
                };

                try self.registerDevice(device, source, true, null);
            }
        }
    }

    /// Enregistrer un dispositif
    pub fn registerDevice(
        self: *Self,
        device: *BlockDevice,
        source: DeviceSource,
        auto_discovered: bool,
        params: ?[]const u8,
    ) !void {
        self.mutex.acquire();
        defer self.mutex.release();

        // Vérifier l'unicité du nom
        for (self.devices.items) |existing| {
            if (std.mem.eql(u8, existing.device.getName(), device.getName())) {
                return BlockError.DeviceExists;
            }
        }

        // Sauvegarder les paramètres si fournis
        const saved_params = if (params) |p| try allocator.dupe(u8, p) else null;

        try self.devices.append(.{
            .device = device,
            .source = source,
            .auto_discovered = auto_discovered,
            .creation_params = saved_params,
        });

        logger.info("Registered {s}: {s} ({} blocks of {} bytes)", .{
            @tagName(source),
            device.getName(),
            device.total_blocks,
            device.block_size,
        });
    }

    /// Créer un dispositif personnalisé
    pub fn createDevice(self: *Self, source: DeviceSource, params: []const u8) !*BlockDevice {
        const provider = self.providers.get(source) orelse {
            logger.err("No provider for {s}", .{@tagName(source)});
            return BlockError.NotSupported;
        };

        const device = try provider.createCustom(params);
        try self.registerDevice(device, source, false, params);

        logger.info("Created custom {s} device: {s}", .{ @tagName(source), device.getName() });
        return device;
    }

    /// Supprimer un dispositif
    pub fn removeDevice(self: *Self, name: []const u8) !void {
        self.mutex.acquire();
        defer self.mutex.release();

        for (self.devices.items, 0..) |*reg_device, i| {
            if (std.mem.eql(u8, reg_device.device.getName(), name)) {
                // Vérifier si le dispositif peut être supprimé
                if (reg_device.auto_discovered and reg_device.source == .IDE) {
                    return BlockError.NotSupported; // Pas de suppression des disques physiques
                }

                self.cleanupDevice(reg_device);
                reg_device.deinit();
                _ = self.devices.swapRemove(i);

                logger.info("Removed device: {s}", .{name});
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

    /// Lister tous les dispositifs
    pub fn list(self: *Self) void {
        self.mutex.acquire();
        defer self.mutex.release();

        logger.info("=== Block Devices ({} total) ===", .{self.devices.items.len});

        for (self.devices.items) |reg_device| {
            const device = reg_device.device;
            const size_mb = (device.total_blocks * device.block_size) / (1024 * 1024);

            logger.info("{s}: {s}, {} MB, Source: {s}, {s}", .{
                device.getName(),
                @tagName(device.device_type),
                size_mb,
                @tagName(reg_device.source),
                if (reg_device.auto_discovered) "auto" else "manual",
            });

            if (reg_device.creation_params) |params| {
                logger.info("  Creation params: {s}", .{params});
            }

            logger.info("  Features: R:{} W:{} Removable:{}", .{
                device.features.readable,
                device.features.writable,
                device.features.removable,
            });

            logger.info("  Stats: Reads:{} Writes:{} Errors:{}", .{
                device.stats.reads_completed,
                device.stats.writes_completed,
                device.stats.errors,
            });
        }
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
            .IDE => {
                const BlockIDE = @import("../../devices/block_ide/device.zig").BlockIDE;
                const ide_device: *BlockIDE = @fieldParentPtr("base", reg_device.device);
                ide_device.destroy();
            },
            .RAM => {
                const BlockRamDisk = @import("../../devices/block_ram_disk/device.zig").BlockRamDisk;
                const ram_device: *BlockRamDisk = @fieldParentPtr("base", reg_device.device);
                ram_device.destroy();
            },
            else => {
                logger.warn("No cleanup for device type: {s}", .{@tagName(reg_device.source)});
            },
        }
    }
};
