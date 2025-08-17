pub const types = @import("_core/types.zig");

pub const benchmark = @import("_core/benchmark.zig");

pub const translator = @import("_core/translator.zig");
pub const BlockTranslator = translator.BlockTranslator;
pub const ScaledTranslator = translator.ScaledTranslator;
pub const DirectTranslator = translator.DirectTranslator;

pub const device_manager = @import("_core/device_manager.zig");
pub const DeviceManager = device_manager.DeviceManager;
pub const DeviceProvider = device_manager.DeviceProvider;

pub const BlockDevice = @import("_core/block_device.zig");
pub const BufferCache = @import("_core/buffer_cache.zig");

// Exposes the main block device and their providers
//
pub const BlockDevDisk = @import("disk/device.zig");
pub const BlockDevDiskProvider = @import("disk/provider.zig");

pub const BlockDevCD = @import("cdrom/device.zig");
pub const BlockDevProvider = @import("cdrom/provider.zig");

pub const BlockDevRam = @import("ramdisk/device.zig");
pub const BlockDevRamProvider = @import("ramdisk/provider.zig");

// Standard logical block size for all block devices
pub const STANDARD_BLOCK_SIZE: u32 = 512;
