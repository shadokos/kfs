// src/storage/device_registry.zig
// Nouveau système unifié pour la gestion des dispositifs

const std = @import("std");
const ArrayList = std.ArrayList;
const BlockDevice = @import("block_device.zig").BlockDevice;
const BlockError = @import("block_device.zig").BlockError;
const DeviceManager = @import("device_manager.zig").DeviceManager;
const logger = std.log.scoped(.device_registry);
const allocator = @import("../memory.zig").smallAlloc.allocator();

const IDEBlockDevice = @import("ide_device.zig").IDEBlockDevice;
const RamDisk = @import("brd.zig").RamDisk;

/// Types de dispositifs supportés
pub const DeviceProviderType = enum {
    IDE,
    RAM,
    Loop,
    Network, // iSCSI, NBD, etc.
    Future, // Extensible
};

/// Interface pour les fournisseurs de dispositifs
pub const DeviceProvider = struct {
    vtable: *const VTable,
    context: *anyopaque,
    provider_type: DeviceProviderType,

    const VTable = struct {
        /// Découverte automatique des dispositifs (retourne le nombre trouvé)
        discover: *const fn (ctx: *anyopaque) u32,

        /// Créer un dispositif découvert par index
        createDiscovered: *const fn (ctx: *anyopaque, index: u32) anyerror!*BlockDevice,

        /// Créer un dispositif avec paramètres personnalisés
        createCustom: ?*const fn (ctx: *anyopaque, params: []const u8) anyerror!*BlockDevice,

        /// Nettoyer les ressources
        deinit: *const fn (ctx: *anyopaque) void,

        /// Nom du fournisseur
        getName: *const fn (ctx: *anyopaque) []const u8,
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

    pub fn getName(self: *DeviceProvider) []const u8 {
        return self.vtable.getName(self.context);
    }

    pub fn deinit(self: *DeviceProvider) void {
        self.vtable.deinit(self.context);
    }
};

/// Registre unifié des dispositifs
pub const DeviceRegistry = struct {
    device_manager: *DeviceManager,
    providers: ArrayList(*DeviceProvider),
    registered_devices: ArrayList(RegisteredDevice),

    const RegisteredDevice = struct {
        device: *BlockDevice,
        provider_type: DeviceProviderType,
        is_auto_discovered: bool,
        params: ?[]const u8, // Pour les devices créés manuellement
    };

    const Self = @This();

    pub fn init(device_manager: *DeviceManager) Self {
        return .{
            .device_manager = device_manager,
            .providers = ArrayList(*DeviceProvider).init(allocator),
            .registered_devices = ArrayList(RegisteredDevice).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        // Nettoyer tous les devices enregistrés
        for (self.registered_devices.items) |reg_device| {
            self.device_manager.unregister(reg_device.device.getName()) catch {};

            // Appeler la fonction de nettoyage spécifique selon le type
            switch (reg_device.provider_type) {
                .IDE => {
                    const ide_device: IDEBlockDevice = @fieldParentPtr("base", reg_device.device);
                    ide_device.destroy();
                },
                .RAM => {
                    const ram_device: RamDisk = @fieldParentPtr("base", reg_device.device);
                    ram_device.destroy();
                },
                else => {
                    // Pour les futurs types, ils devront implémenter leur propre nettoyage
                    logger.warn("No cleanup method for device type: {}", .{reg_device.provider_type});
                },
            }

            if (reg_device.params) |params| {
                allocator.free(params);
            }
        }

        // Nettoyer les providers
        for (self.providers.items) |provider| {
            provider.deinit();
        }

        self.registered_devices.deinit();
        self.providers.deinit();
    }

    /// Enregistrer un fournisseur de dispositifs
    pub fn registerProvider(self: *Self, provider: *DeviceProvider) !void {
        try self.providers.append(provider);
        logger.info("Registered device provider: {s}", .{provider.getName()});
    }

    /// Découverte automatique de tous les dispositifs
    pub fn discoverAll(self: *Self) !void {
        logger.info("=== Auto-discovering devices ===", .{});

        for (self.providers.items) |provider| {
            const count = provider.discover();
            logger.info("Provider {s}: found {} devices", .{ provider.getName(), count });

            for (0..count) |i| {
                const device = provider.createDiscovered(@truncate(i)) catch |err| {
                    logger.err("Failed to create device {} from {s}: {}", .{ i, provider.getName(), err });
                    continue;
                };

                try self.device_manager.register(device);

                try self.registered_devices.append(.{
                    .device = device,
                    .provider_type = provider.provider_type,
                    .is_auto_discovered = true,
                    .params = null,
                });

                logger.info("Auto-registered: {s}", .{device.getName()});
            }
        }
    }

    /// Créer et enregistrer un dispositif personnalisé
    pub fn createDevice(self: *Self, provider_type: DeviceProviderType, params: []const u8) !*BlockDevice {
        // Trouver le provider approprié
        for (self.providers.items) |provider| {
            if (provider.provider_type == provider_type) {
                const device = try provider.createCustom(params);
                try self.device_manager.register(device);

                // Sauvegarder les paramètres pour le nettoyage
                const saved_params = try allocator.dupe(u8, params);

                try self.registered_devices.append(.{
                    .device = device,
                    .provider_type = provider_type,
                    .is_auto_discovered = false,
                    .params = saved_params,
                });

                logger.info("Manually created device: {s} (type: {s})", .{
                    device.getName(),
                    @tagName(provider_type),
                });

                return device;
            }
        }

        logger.err("No provider found for type: {s}", .{@tagName(provider_type)});
        return BlockError.NotSupported;
    }

    /// Supprimer un dispositif
    pub fn removeDevice(self: *Self, device_name: []const u8) !void {
        for (self.registered_devices.items, 0..) |reg_device, i| {
            if (std.mem.eql(u8, reg_device.device.getName(), device_name)) {
                try self.device_manager.unregister(device_name);

                // Nettoyer selon le type
                switch (reg_device.provider_type) {
                    .IDE => {
                        // Les devices IDE ne peuvent pas être supprimés manuellement
                        return BlockError.NotSupported;
                    },
                    .RAM => {
                        const ram_device: RamDisk = @fieldParentPtr("base", reg_device.device);
                        ram_device.destroy();
                    },
                    else => {
                        logger.warn("Manual removal not supported for type: {}", .{reg_device.provider_type});
                        return BlockError.NotSupported;
                    },
                }

                if (reg_device.params) |params| {
                    allocator.free(params);
                }

                _ = self.registered_devices.swapRemove(i);
                logger.info("Removed device: {s}", .{device_name});
                return;
            }
        }

        return BlockError.DeviceNotFound;
    }

    /// Lister tous les dispositifs avec leurs détails
    pub fn listDevices(self: *Self) void {
        logger.info("=== Device Registry ===", .{});

        for (self.registered_devices.items) |reg_device| {
            const device = reg_device.device;
            const size_mb = (device.total_blocks * device.block_size) / (1024 * 1024);

            logger.info("{s}: {s}, {} MB, {s}, {s}", .{
                device.getName(),
                @tagName(device.device_type),
                size_mb,
                @tagName(reg_device.provider_type),
                if (reg_device.is_auto_discovered) "auto" else "manual",
            });

            if (reg_device.params) |params| {
                logger.info("  Params: {s}", .{params});
            }
        }
    }

    /// API de convenance pour créer des RAM disks
    pub fn createRamDisk(self: *Self, name: []const u8, size_mb: u32, block_size: u32) !*BlockDevice {
        const params = try std.fmt.allocPrint(allocator, "{s}:{d}:{d}", .{ name, size_mb, block_size });
        defer allocator.free(params);

        return self.createDevice(.RAM, params);
    }
};

// Providers spécifiques

/// Provider pour les dispositifs IDE
const IDEProvider = struct {
    base: DeviceProvider,

    const ide = @import("../drivers/ide/ide.zig");

    const vtable = DeviceProvider.VTable{
        .discover = discover,
        .createDiscovered = createDiscovered,
        .createCustom = null, // Pas de création personnalisée pour IDE
        .deinit = deinitProvider,
        .getName = getName,
    };

    pub fn create() !*IDEProvider {
        const provider = try allocator.create(IDEProvider);
        provider.* = .{
            .base = .{
                .vtable = &vtable,
                .context = provider,
                .provider_type = .IDE,
            },
        };
        return provider;
    }

    fn discover(ctx: *anyopaque) u32 {
        _ = ctx;
        return ide.getDriveCount();
    }

    fn createDiscovered(ctx: *anyopaque, index: u32) !*BlockDevice {
        _ = ctx;
        const ide_device = try IDEBlockDevice.create(index);
        return &ide_device.base;
    }

    fn getName(ctx: *anyopaque) []const u8 {
        _ = ctx;
        return "IDE Controller";
    }

    fn deinitProvider(ctx: *anyopaque) void {
        const self: *IDEProvider = @ptrCast(@alignCast(ctx));
        allocator.destroy(self);
    }
};

/// Provider pour les RAM disks
const RAMProvider = struct {
    base: DeviceProvider,

    const vtable = DeviceProvider.VTable{
        .discover = discover,
        .createDiscovered = createDiscovered,
        .createCustom = createCustom,
        .deinit = deinitProvider,
        .getName = getName,
    };

    pub fn create() !*RAMProvider {
        const provider = try allocator.create(RAMProvider);
        provider.* = .{
            .base = .{
                .vtable = &vtable,
                .context = provider,
                .provider_type = .RAM,
            },
        };
        return provider;
    }

    fn discover(ctx: *anyopaque) u32 {
        _ = ctx;
        // Pas de découverte automatique pour les RAM disks
        return 0;
    }

    fn createDiscovered(ctx: *anyopaque, index: u32) !*BlockDevice {
        _ = ctx;
        _ = index;
        return BlockError.NotSupported;
    }

    fn createCustom(ctx: *anyopaque, params: []const u8) !*BlockDevice {
        _ = ctx;

        // Parser les paramètres: "name:size_mb:block_size"
        var it = std.mem.splitAny(u8, params, ":");

        const name = it.next() orelse return BlockError.InvalidOperation;
        const size_str = it.next() orelse return BlockError.InvalidOperation;
        const block_size_str = it.next() orelse return BlockError.InvalidOperation;

        const size_mb = std.fmt.parseInt(u32, size_str, 10) catch return BlockError.InvalidOperation;
        const block_size = std.fmt.parseInt(u32, block_size_str, 10) catch return BlockError.InvalidOperation;

        const ramdisk = try RamDisk.create(name, size_mb, block_size);
        return &ramdisk.base;
    }

    fn getName(ctx: *anyopaque) []const u8 {
        _ = ctx;
        return "RAM Disk Provider";
    }

    fn deinitProvider(ctx: *anyopaque) void {
        const self: *RAMProvider = @ptrCast(@alignCast(ctx));
        allocator.destroy(self);
    }
};

/// Fonctions de convenance pour créer les providers
pub fn createIDEProvider() !*DeviceProvider {
    const provider = try IDEProvider.create();
    return &provider.base;
}

pub fn createRAMProvider() !*DeviceProvider {
    const provider = try RAMProvider.create();
    return &provider.base;
}
