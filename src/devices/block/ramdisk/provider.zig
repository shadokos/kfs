const std = @import("std");
const DeviceProvider = @import("../../../storage/block/device_manager.zig").DeviceProvider;
const BlockDevice = @import("../../../storage/block/block_device.zig").BlockDevice;
const BlockError = @import("../../../storage/block/block_device.zig").BlockError;
const BlockRam = @import("device.zig");
const allocator = @import("../../../memory.zig").smallAlloc.allocator();
const logger = std.log.scoped(.ram_provider);

const Self = @This();

base: DeviceProvider,

pub const CreateParams = struct {
    name: []const u8,
    size_mb: u32,
    block_size: u32,
};

const vtable = DeviceProvider.VTable{
    .discover = discover,
    .create = @ptrCast(&create),
    .deinit = deinit,
};

pub fn init() !*Self {
    const provider = try allocator.create(Self);
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

fn create(ctx: *anyopaque, params: *CreateParams) !*BlockDevice {
    _ = ctx;

    // Valider les paramètres
    if (params.size_mb == 0) {
        logger.err("Invalid RAM disk size: {} MB (must be at least 1 MB)", .{params.size_mb});
        return BlockError.InvalidOperation;
    }

    if (params.block_size < 512 or params.block_size > 4096 or params.block_size % 512 != 0) {
        logger.err("Invalid block size: {} (Size must be 512–4096 bytes and a multiple of 512 bytes)", .{
            params.block_size,
        });
        return BlockError.InvalidOperation;
    }

    logger.info("Creating RAM disk: {s}, {} MB, {} byte blocks", .{ params.name, params.size_mb, params.block_size });

    const ramdisk = try BlockRam.create(params.name, params.size_mb, params.block_size);
    return &ramdisk.base;
}

fn deinit(ctx: *anyopaque) void {
    const self: *Self = @ptrCast(@alignCast(ctx));
    allocator.destroy(self);
}
