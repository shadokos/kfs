const std = @import("std");
const allocator = @import("../../../memory.zig").bigAlloc.allocator();
const logger = std.log.scoped(.disk_provider);

const core = @import("../core.zig");
const types = core.types;

const BlockDevice = core.BlockDevice;
const BlockProvider = core.BlockProvider;

// TODO: Refactor the storage module
// const storage = &@import("../../../storage/storage.zig");

const BlockDisk = @import("device.zig");

const ide = @import("../../../drivers/ide/ide.zig");

const Self = @This();

// Provider are singleton
var instance: ?Self = null;

base: BlockProvider,

pub const CreateParams = struct {
    info: ide.types.DriveInfo,
    channel: *ide.Channel,
};

const vtable = BlockProvider.VTable{
    .discover = discover,
    .create = @ptrCast(&create),
    .deinit = deinit,
};

pub fn init() *Self {
    if (instance) |*existing| return existing;
    instance = .{
        .base = .{
            .vtable = &vtable,
            .context = @ptrCast(&instance),
        },
    };
    return &instance.?;
}

fn discover(ctx: *anyopaque) u32 {
    _ = ctx;
    var count: u32 = 0;
    for (ide.channels) |*channel| {
        for ([_]ide.Channel.DrivePosition{ .Master, .Slave }) |position| {
            if (try ide.ata.detectDrive(channel, position)) |info| {
                // TODO: Maybe add some logging if an error occurs
                const manager = core.getManager();
                const registered = manager.createDevice(
                    .DISK,
                    @constCast(@ptrCast(&CreateParams{
                        .info = info,
                        .channel = channel,
                    })),
                ) catch continue; // If registration fails, continue to next drive
                registered.auto_discovered = true;
                logger.debug("{s} registered ({s}, {s})", .{
                    registered.device.getName(),
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
    const disk = try BlockDisk.create(params.info, params.channel);
    return &disk.base;
}

fn deinit(ctx: *anyopaque) void {
    const self: *Self = @ptrCast(@alignCast(ctx));
    allocator.destroy(self);
}
