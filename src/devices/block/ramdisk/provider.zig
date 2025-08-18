const std = @import("std");
const allocator = @import("../../../memory.zig").smallAlloc.allocator();
const logger = std.log.scoped(.ram_provider);

const core = @import("../core.zig");
const types = core.types;

const BlockDevice = core.BlockDevice;
const BlockProvider = core.BlockProvider;

const BlockRam = @import("device.zig");

pub const Source = types.DeviceSource.RAM;

const Self = @This();

// Providers are singleton
var instance: ?Self = null;

base: BlockProvider,

pub const CreateParams = struct {
    size_mb: u32,
    block_size: u32,
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
            .major = @intFromEnum(Source),
        },
    };
    instance.?.base.init_slots();
    return &instance.?;
}

fn discover(ctx: *anyopaque) u32 {
    _ = ctx;
    // The RAM disk provider does not discover devices dynamically.
    return 0;
}

fn create(ctx: *anyopaque, params: *CreateParams) !BlockDevice {
    _ = ctx;
    const ramdisk = try BlockRam.create(params.size_mb, params.block_size);
    return ramdisk.base;
}

fn deinit(ctx: *anyopaque) void {
    _ = ctx;
    // const self: *Self = @ptrCast(@alignCast(ctx));
    // allocator.destroy(self);
}
