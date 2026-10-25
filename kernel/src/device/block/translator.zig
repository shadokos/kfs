const std = @import("std");

const core = @import("block.zig");
const STANDARD_BLOCK_SIZE = core.STANDARD_BLOCK_SIZE;

pub const BlockTranslator = @import("translators/base.zig");
pub const IdentityTranslator = @import("translators/identity.zig");
pub const ScaledTranslator = @import("translators/scaled.zig");

/// Represents a range of physical blocks
pub const PhysicalRange = struct {
    physical_start: u32,
    physical_count: u32,
};

/// Translation operation result
pub const TranslationOp = struct {
    physical_start: u32,
    physical_count: u32,
    buffer_offset: usize,
    buffer_size: usize,
    needs_rmw: bool, // Read-modify-write required
    rmw_offset: usize, // Offset within physical block for partial operations
    rmw_size: usize, // Size of data to copy for partial operations
};

pub const VTable = struct {
    /// Convert logical block address to physical
    logicalToPhysical: *const fn (ctx: *anyopaque, logical: u32) u32,

    /// Calculate how many physical blocks are needed for logical range
    calculatePhysicalRange: *const fn (
        ctx: *anyopaque,
        logical_start: u32,
        logical_count: u32,
    ) PhysicalRange,

    /// Plan translation operations for a logical I/O request
    planOperations: *const fn (
        ctx: *anyopaque,
        logical_start: u32,
        logical_count: u32,
        ops: []TranslationOp,
    ) u32,

    /// Destroy the translator
    deinit: *const fn (ctx: *anyopaque) void,
};

/// Create appropriate translator for given block sizes
pub fn create(allocator: std.mem.Allocator, physical_block_size: u32) !*BlockTranslator {
    if (physical_block_size == STANDARD_BLOCK_SIZE) {
        const direct = try IdentityTranslator.create(allocator, physical_block_size);
        return &direct.base;
    } else {
        const scaled = try ScaledTranslator.create(allocator, physical_block_size);
        return &scaled.base;
    }
}

pub fn destroy(translator: *BlockTranslator) void {
    translator.vtable.deinit(translator.context);
}
