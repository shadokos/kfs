// src/storage/ram_provider.zig
// Provider pour les RAM disks

const std = @import("std");
const DeviceProvider = @import("../../storage/block/device_manager.zig").DeviceProvider;
const BlockDevice = @import("../../storage/block/block_device.zig").BlockDevice;
const BlockError = @import("../../storage/block/block_device.zig").BlockError;
const BlockRamDisk = @import("device.zig").BlockRamDisk;
const logger = std.log.scoped(.ram_provider);
const allocator = @import("../../memory.zig").smallAlloc.allocator();

pub const RAMProvider = struct {
    base: DeviceProvider,

    const vtable = DeviceProvider.VTable{
        .discover = discover,
        .createDiscovered = createDiscovered,
        .createCustom = createCustom,
        .deinit = deinitProvider,
    };

    pub fn create() !*RAMProvider {
        const provider = try allocator.create(RAMProvider);
        provider.* = .{
            .base = .{
                .vtable = &vtable,
                .context = provider,
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

        const name = it.next() orelse {
            logger.err("Missing name in RAM disk params", .{});
            return BlockError.InvalidOperation;
        };

        const size_str = it.next() orelse {
            logger.err("Missing size in RAM disk params", .{});
            return BlockError.InvalidOperation;
        };

        const block_size_str = it.next() orelse {
            logger.err("Missing block size in RAM disk params", .{});
            return BlockError.InvalidOperation;
        };

        const size_mb = std.fmt.parseInt(u32, size_str, 10) catch {
            logger.err("Invalid size: {s}", .{size_str});
            return BlockError.InvalidOperation;
        };

        const block_size = std.fmt.parseInt(u32, block_size_str, 10) catch {
            logger.err("Invalid block size: {s}", .{block_size_str});
            return BlockError.InvalidOperation;
        };

        // Valider les paramètres
        if (size_mb == 0 or size_mb > 1024) {
            logger.err("Invalid RAM disk size: {} MB (must be 1-1024)", .{size_mb});
            return BlockError.InvalidOperation;
        }

        if (block_size < 512 or block_size > 4096 or block_size % 512 != 0) {
            logger.err("Invalid block size: {} (must be 512, 1024, 2048, or 4096)", .{block_size});
            return BlockError.InvalidOperation;
        }

        logger.info("Creating RAM disk: {s}, {} MB, {} byte blocks", .{ name, size_mb, block_size });

        const ramdisk = try BlockRamDisk.create(name, size_mb, block_size);
        return &ramdisk.base;
    }

    fn deinitProvider(ctx: *anyopaque) void {
        const self: *RAMProvider = @ptrCast(@alignCast(ctx));
        allocator.destroy(self);
    }
};
