const std = @import("std");
const ide = @import("../../drivers/ide/ide.zig");
const device_manager = @import("../../storage/block/device_manager.zig");
const BlockDevice = @import("../../storage/block/block_device.zig").BlockDevice;
const BlockIDE = @import("device.zig").BlockIDE;
const allocator = @import("../../memory.zig").bigAlloc.allocator();
const logger = std.log.scoped(.ide_block);

pub const IDEProvider = struct {
    base: device_manager.DeviceProvider,

    const vtable = device_manager.DeviceProvider.VTable{
        .discover = discover,
        .createDiscovered = createDiscovered,
        .createCustom = null, // Pas de création personnalisée pour IDE
        .deinit = deinitProvider,
    };

    pub fn create() !*IDEProvider {
        const provider = try allocator.create(IDEProvider);
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
        const count = ide.getDriveCount();
        logger.info("IDEProvider: discovering {} drives", .{count});
        return @truncate(count);
    }

    fn createDiscovered(ctx: *anyopaque, index: u32) !*BlockDevice {
        _ = ctx;
        const ide_device = try BlockIDE.create(index);
        logger.info("IDEProvider: successfully created block device {s}", .{
            ide_device.base.getName(),
        });

        return &ide_device.base;
    }

    fn deinitProvider(ctx: *anyopaque) void {
        const self: *IDEProvider = @ptrCast(@alignCast(ctx));
        allocator.destroy(self);
    }
};
