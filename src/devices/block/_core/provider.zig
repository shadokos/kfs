const core = @import("../core.zig");
const BlockDevice = core.BlockDevice;

pub const MAX_DEVICES_PER_PROVIDER: u8 = 64;
const SlotManager = @import("../../../misc/slot_manager.zig").SlotManager(BlockDevice, MAX_DEVICES_PER_PROVIDER);

pub const VTable = struct {
    /// Automatic discovery (returns the number of devices found)
    discover: *const fn (ctx: *anyopaque) u32,

    /// Create a device with parameters
    create: *const fn (ctx: *anyopaque, params: *const void) anyerror!BlockDevice,

    // destroy: *const fn (self: *Self, device: *BlockDevice) void,

    /// Clean up provider resources
    deinit: *const fn (ctx: *anyopaque) void,
};

const Self = @This();

/// Interface for device providers
vtable: *const VTable,
context: *anyopaque,
major: u8,

slots: SlotManager = undefined,

pub fn discover(self: *Self) u32 {
    return self.vtable.discover(self.context);
}

pub fn create(self: *Self, params: *const void) !*BlockDevice {
    const device = try self.vtable.create(self.context, params);

    const index: usize, const dev: *BlockDevice = try self.slots.create(device);

    dev.minor = @truncate(index);
    dev.major = self.major;

    try dev.generateName();
    // if (dev.vtable.generate_name) |generate_name| {
    //     const name = generate_name(dev.minor);
    //     @memcpy(dev.name[0..16], name[0..16]);
    // }

    return dev;
}

pub fn destroy(self: *Self, minor: u8) void {
    self.slots.destroy(minor) catch return;
}

pub fn init_slots(self: *Self) void {
    self.slots = SlotManager.init();
}
pub fn deinit(self: *Self) void {
    self.vtable.deinit(self.context);
}
