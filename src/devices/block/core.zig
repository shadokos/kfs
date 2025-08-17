pub const types = @import("_core/types.zig");

pub const benchmark = @import("_core/benchmark.zig");

pub const translator = @import("_core/translator.zig");
pub const BlockTranslator = translator.BlockTranslator;
pub const ScaledTranslator = translator.ScaledTranslator;
pub const DirectTranslator = translator.DirectTranslator;

pub const BlockManager = @import("_core/manager.zig");
pub const BlockProvider = @import("_core/provider.zig");
pub const BlockDevice = @import("_core/blockdev.zig");
pub const BufferCache = @import("_core/buffer_cache.zig");

// Exposes the main block device and their providers
//
pub const Disk = @import("disk/device.zig");
pub const DiskProvider = @import("disk/provider.zig");

pub const CD = @import("cdrom/device.zig");
pub const CDProvider = @import("cdrom/provider.zig");

pub const Ram = @import("ramdisk/device.zig");
pub const RamProvider = @import("ramdisk/provider.zig");

const provider_definitions = .{
    .{ .DISK, DiskProvider },
    .{ .CDROM, CDProvider },
    .{ .RAM, RamProvider },
};

// Standard logical block size for all block devices
pub const STANDARD_BLOCK_SIZE: u32 = 512;

const std = @import("std");
const ide = @import("../../drivers/ide/ide.zig");
const allocator = @import("../../memory.zig").smallAlloc.allocator();
const logger = std.log.scoped(.blockdev);

var manager: BlockManager = BlockManager.init();
var buffer_cache: ?BufferCache = null; // needs runtime initialization

fn is_initialized() bool {
    return buffer_cache != null;
}

pub fn init() !void {
    if (is_initialized()) return;

    try ide.init();

    buffer_cache = try BufferCache.init();

    // Initialize provd
    inline for (provider_definitions) |definition| {
        skip: {
            const source, const provider = definition;
            const instance = provider.init();
            manager.registerProvider(source, &instance.base) catch |err| {
                logger.warn("failed to register {s} provider: {s}", .{ @tagName(source), @errorName(err) });
                break :skip;
            };
            _ = instance.base.discover();
        }
    }
}

pub fn getManager() *BlockManager {
    return &manager;
}
