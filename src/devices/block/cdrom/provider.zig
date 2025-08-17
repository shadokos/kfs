const std = @import("std");
const allocator = @import("../../../memory.zig").bigAlloc.allocator();
const logger = std.log.scoped(.cd_provider);

const core = @import("../core.zig");
const types = core.types;

const BlockDevice = core.BlockDevice;
const DeviceProvider = core.DeviceProvider;

// TODO: Refactor the storage module
const storage = &@import("../../../storage/storage.zig");

const BlockCD = @import("device.zig");

const ide = @import("../../../drivers/ide/ide.zig");

const Self = @This();

base: DeviceProvider,

pub const CreateParams = struct {
    info: ide.types.DriveInfo,
    channel: *ide.Channel,
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
    var count: u32 = 0;
    for (ide.channels) |*channel| {
        for ([_]ide.Channel.DrivePosition{ .Master, .Slave }) |position| {
            if (try ide.atapi.detectDrive(channel, position)) |info| {
                // TODO: Maybe add some logging if an error occurs
                const device_manager = storage.getManager();
                const dev = device_manager.createDevice(
                    .CDROM,
                    @constCast(@ptrCast(&CreateParams{
                        .info = info,
                        .channel = channel,
                    })),
                ) catch continue; // If registration fails, continue to next drive
                logger.debug("{s} registered ({s}, {s})", .{
                    dev.getName(),
                    @tagName(channel.channel_type),
                    @tagName(position),
                });
                count += 1;
            }
        }
    }
    return count;
}

fn create(ctx: *anyopaque, params: *const CreateParams) !*BlockDevice {
    _ = ctx;
    const disk = try BlockCD.create(params.info, params.channel);
    return &disk.base;
}

fn deinit(ctx: *anyopaque) void {
    const self: *Self = @ptrCast(@alignCast(ctx));
    allocator.destroy(self);
}
