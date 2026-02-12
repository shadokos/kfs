// MBR (Master Boot Record) Partition Table Parser
//
// Layout at sector 0, offset 0x1BE:
// +-------+------------------+
// | Bytes | Content          |
// +-------+------------------+
// | 0-445 | Boot code        |
// | 446   | Partition 1      |
// | 462   | Partition 2      |
// | 478   | Partition 3      |
// | 494   | Partition 4      |
// | 510   | Signature 0xAA55 |
// +-------+------------------+

const std = @import("std");

const partitions = @import("partitions.zig");
const ParseContext = partitions.ParseContext;
const ParseResult = partitions.ParseResult;

const blk = @import("../block.zig");
const GenDisk = @import("../gendisk.zig");
const STANDARD_BLOCK_SIZE = blk.STANDARD_BLOCK_SIZE;

const logger = std.log.scoped(.mbr);

/// MBR Signature - must be at bytes 510-511
pub const MBR_SIGNATURE: u16 = 0xAA55;

/// Partition table offset in MBR
pub const PARTITION_TABLE_OFFSET: usize = 446;

/// Maximum EBR chain depth to prevent infinite loops
const MAX_EBR_DEPTH: usize = 128;

/// Partition type IDs
pub const PartitionType = enum(u8) {
    Empty = 0x00,
    FAT12 = 0x01,
    FAT16_Small = 0x04,
    Extended_CHS = 0x05,
    FAT16 = 0x06,
    NTFS = 0x07,
    FAT32_CHS = 0x0B,
    FAT32_LBA = 0x0C,
    FAT16_LBA = 0x0E,
    Extended_LBA = 0x0F,
    Hidden_FAT12 = 0x11,
    Hidden_FAT16 = 0x14,
    Hidden_FAT32 = 0x1B,
    Hidden_FAT32_LBA = 0x1C,
    Hidden_FAT16_LBA = 0x1E,
    LinuxSwap = 0x82,
    LinuxNative = 0x83,
    LinuxExtended = 0x85,
    LinuxLVM = 0x8E,
    GPT_Protective = 0xEE,
    EFI_System = 0xEF,
    LinuxRAID = 0xFD,
    _,

    pub fn isExtended(self: PartitionType) bool {
        return self == .Extended_CHS or self == .Extended_LBA;
    }

    pub fn isEmpty(self: PartitionType) bool {
        return self == .Empty;
    }

    pub fn displayName(self: PartitionType) []const u8 {
        return switch (self) {
            .Empty => "Empty",
            .FAT12 => "FAT12",
            .FAT16_Small => "FAT16 <32M",
            .Extended_CHS => "Extended",
            .FAT16 => "FAT16",
            .NTFS => "NTFS/exFAT",
            .FAT32_CHS => "FAT32",
            .FAT32_LBA => "FAT32 LBA",
            .FAT16_LBA => "FAT16 LBA",
            .Extended_LBA => "Extended LBA",
            .Hidden_FAT12 => "Hidden FAT12",
            .Hidden_FAT16 => "Hidden FAT16",
            .Hidden_FAT32 => "Hidden FAT32",
            .Hidden_FAT32_LBA => "Hidden FAT32 LBA",
            .Hidden_FAT16_LBA => "Hidden FAT16 LBA",
            .LinuxSwap => "Linux swap",
            .LinuxNative => "Linux",
            .LinuxExtended => "Linux extended",
            .LinuxLVM => "Linux LVM",
            .GPT_Protective => "GPT",
            .EFI_System => "EFI System",
            .LinuxRAID => "Linux RAID",
            _ => "Unknown",
        };
    }
};

/// MBR Partition Entry (16 bytes)
/// Uses extern struct for exact memory layout matching disk format
pub const PartitionEntry = extern struct {
    /// Boot indicator: 0x80 = bootable, 0x00 = inactive
    status: enum(u8) {
        Inactive = 0x00,
        Bootable = 0x80,
    },
    /// CHS address of first sector (legacy, we use LBA)
    chs_first: CHS,
    /// Partition type ID
    type_id: PartitionType,
    /// CHS address of last sector (legacy)
    chs_last: CHS,
    /// LBA of first sector (little-endian)
    lba_start: u32 align(1),
    /// Number of sectors (little-endian)
    lba_sectors: u32 align(1),

    const CHS = extern struct {
        head: u8,
        sector_cylinder: u8, // Sector in bits 0-5, cylinder high in 6-7
        cylinder_low: u8,
    };

    pub fn isValid(self: *const PartitionEntry) bool {
        // Entry is valid if type is not empty and has sectors
        return !self.type_id.isEmpty() and self.lba_sectors > 0;
    }

    pub fn isBootable(self: *const PartitionEntry) bool {
        return self.status == .Bootable;
    }

    pub fn isExtended(self: *const PartitionEntry) bool {
        return self.type_id.isExtended();
    }
};

/// MBR structure (512 bytes)
pub const MBR = extern struct {
    _: [446]u8, // raw MBR bootstrap / reserved bytes
    partitions: [4]PartitionEntry,
    signature: u16 align(1),

    comptime {
        if (@sizeOf(MBR) != 512) {
            @compileError("MBR struct size must be exactly 512 bytes");
        }
        if (@sizeOf(PartitionEntry) != 16) {
            @compileError("PartitionEntry struct size must be exactly 16 bytes");
        }
    }

    /// Cast a sector buffer to MBR
    /// Returns null if the buffer is too small to hold an MBR
    pub fn fromSector(sector: []const u8) ?*const MBR {
        if (sector.len < @sizeOf(MBR)) return null;
        return @ptrCast(@alignCast(sector.ptr));
    }

    pub fn isValid(self: *const MBR) bool {
        // MBR signature is stored as 0x55 0xAA on disk (little-endian = 0xAA55)
        // Since we're on x86 (little-endian), no conversion needed
        logger.debug("MBR signature check: 0x{X:0>4} (expected 0x{X:0>4})", .{ self.signature, MBR_SIGNATURE });
        return self.signature == MBR_SIGNATURE;
    }

    /// Iterator over valid partition entries
    pub fn validPartitions(self: *const MBR) ValidPartitionIterator {
        return .{ .mbr = self, .index = 0 };
    }

    pub const ValidPartitionIterator = struct {
        mbr: *const MBR,
        index: usize,

        pub fn next(self: *ValidPartitionIterator) ?*const PartitionEntry {
            while (self.index < 4) {
                const entry = &self.mbr.partitions[self.index];
                self.index += 1;
                if (entry.isValid()) {
                    return entry;
                }
            }
            return null;
        }
    };
};

/// Parse MBR partition table
pub fn parse(ctx: *ParseContext, sector0: []const u8) ParseResult {
    const mbr = MBR.fromSector(sector0) orelse return .NotRecognized;

    if (!mbr.isValid()) {
        return .NotRecognized;
    }

    logger.debug("MBR signature valid for disk {s}", .{std.mem.sliceTo(&ctx.disk.name, 0)});

    // Parse primary partitions
    var extended_entry: ?*const PartitionEntry = null;

    for (&mbr.partitions, 0..) |*entry, i| {
        if (!entry.isValid()) continue;

        if (entry.isExtended()) {
            // Save extended partition for later processing
            extended_entry = entry;
            logger.debug("  Primary {}: Extended at LBA {}, {} sectors", .{
                i + 1,
                entry.lba_start,
                entry.lba_sectors,
            });
        } else {
            logger.debug("  Primary {}: Type 0x{X:0>2} at LBA {}, {} sectors", .{
                i + 1,
                @intFromEnum(entry.type_id),
                entry.lba_start,
                entry.lba_sectors,
            });

            const part = ctx.disk.add_partition(entry.lba_start, entry.lba_sectors) catch |e| {
                logger.warn("Failed to add primary partition {}: {s}", .{ i + 1, @errorName(e) });
                continue;
            };
            part.partition_type = entry.type_id;
            part.bootable = entry.isBootable();
        }
    }

    // Parse extended partition chain
    if (extended_entry) |ext| {
        parseExtendedPartitions(ctx, ext.lba_start, ext.lba_start) catch |e| {
            logger.warn("Failed to parse extended partitions: {s}", .{@errorName(e)});
        };
    }

    return .Recognized;
}

/// Parse the linked list of Extended Boot Records
fn parseExtendedPartitions(
    ctx: *ParseContext,
    ebr_lba: u32,
    extended_base: u32,
) !void {
    var current_lba = ebr_lba;
    var depth: usize = 0;

    while (depth < MAX_EBR_DEPTH) : (depth += 1) {
        // Read EBR sector
        ctx.disk.partition_table.items[0].read(current_lba, 1, ctx.buffer) catch |e| {
            logger.warn("Failed to read EBR at LBA {}: {s}", .{ current_lba, @errorName(e) });
            return;
        };

        const ebr = MBR.fromSector(ctx.buffer) orelse return;
        if (!ebr.isValid()) {
            logger.debug("Invalid EBR signature at LBA {}", .{current_lba});
            return;
        }

        // First entry: logical partition (relative to current EBR)
        const logical = &ebr.partitions[0];
        if (logical.isValid() and !logical.isExtended()) {
            const absolute_lba = current_lba + logical.lba_start;

            logger.debug("  Logical: Type 0x{X:0>2} at LBA {}, {} sectors", .{
                @intFromEnum(logical.type_id),
                absolute_lba,
                logical.lba_sectors,
            });

            const part = ctx.disk.add_partition(absolute_lba, logical.lba_sectors) catch |e| {
                logger.warn("Failed to add logical partition at LBA {}: {s}", .{
                    absolute_lba,
                    @errorName(e),
                });
                return;
            };
            part.partition_type = logical.type_id;
            part.bootable = logical.isBootable();
        }

        // Second entry: pointer to next EBR (relative to extended partition start)
        const next_ebr = &ebr.partitions[1];
        if (!next_ebr.isValid()) {
            // End of chain
            break;
        }

        // Next EBR LBA is relative to the extended partition base
        current_lba = extended_base + next_ebr.lba_start;
    }

    if (depth >= MAX_EBR_DEPTH) {
        logger.warn("EBR chain exceeded maximum depth ({}), possible corruption", .{MAX_EBR_DEPTH});
    }
}

/// Parser registration for the partition framework
pub const parser = partitions.PartitionParser{
    .name = "mbr",
    .priority = 100, // Lower priority than GPT (when added)
    .parse = parse,
};
