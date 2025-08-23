const core = @import("../../core.zig");
const BlockDevice = core.BlockDevice;
const PartitionDevice = core.PartitionDevice;

// TODO: Support sub-partitions and/or handle GPT tables
// Since we only plan to handle MBR for now and for simplicity, we'll limit to 4 partitions
main: *BlockDevice,
partitions: [4]?*BlockDevice = .{ null, null, null, null },
