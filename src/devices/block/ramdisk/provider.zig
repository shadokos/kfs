const std = @import("std");
const allocator = @import("../../../memory.zig").smallAlloc.allocator();
const logger = std.log.scoped(.ram_provider);

const core = @import("../core.zig");
const types = core.types;

const BlockDevice = core.BlockDevice;
const DeviceProvider = core.DeviceProvider;

const BlockRam = @import("device.zig");

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
    // The RAM disk provider does not discover devices dynamically.
    return 0;
}

fn create(ctx: *anyopaque, params: *CreateParams) !*BlockDevice {
    _ = ctx;
    const ramdisk = try BlockRam.create(params.name, params.size_mb, params.block_size);
    return &ramdisk.base;
}

fn deinit(ctx: *anyopaque) void {
    const self: *Self = @ptrCast(@alignCast(ctx));
    allocator.destroy(self);
}
