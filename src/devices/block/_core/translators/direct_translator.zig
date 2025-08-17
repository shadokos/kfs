const std = @import("std");

const core = @import("../../core.zig");
const types = core.types;
const STANDARD_BLOCK_SIZE = core.STANDARD_BLOCK_SIZE;

const BlockError = types.BlockError;

const BlockTranslator = core.translator.BlockTranslator;
const PhysicalRange = core.translator.PhysicalRange;
const TranslationOp = core.translator.TranslationOp;
const VTable = core.translator.VTable;

const Self = @This();

/// Direct 1:1 translator (logical == physical)
base: BlockTranslator,
allocator: std.mem.Allocator,

const vtable = VTable{
    .logicalToPhysical = logicalToPhysical,
    .calculatePhysicalRange = calculatePhysicalRange,
    .planOperations = planOperations,
    .deinit = deinitTranslator,
};

pub fn create(allocator: std.mem.Allocator, block_size: u32) !*Self {
    const translator = try allocator.create(Self);
    translator.* = .{
        .base = .{
            .vtable = &vtable,
            .context = translator,
            .physical_block_size = block_size,
            .logical_block_size = block_size,
            .temp_buffer = null,
        },
        .allocator = allocator,
    };
    return translator;
}

fn logicalToPhysical(ctx: *anyopaque, logical: u32) u32 {
    _ = ctx;
    return logical;
}

fn calculatePhysicalRange(
    ctx: *anyopaque,
    logical_start: u32,
    logical_count: u32,
) PhysicalRange {
    _ = ctx;
    return .{
        .physical_start = logical_start,
        .physical_count = logical_count,
    };
}

fn planOperations(
    ctx: *anyopaque,
    logical_start: u32,
    logical_count: u32,
    ops: []TranslationOp,
) u32 {
    _ = ctx;

    if (ops.len == 0) return 0;

    ops[0] = .{
        .physical_start = logical_start,
        .physical_count = logical_count,
        .buffer_offset = 0,
        .buffer_size = logical_count * STANDARD_BLOCK_SIZE,
        .needs_rmw = false,
        .rmw_offset = 0,
        .rmw_size = 0,
    };

    return 1;
}

fn deinitTranslator(ctx: *anyopaque) void {
    const self: *Self = @ptrCast(@alignCast(ctx));
    self.allocator.destroy(self);
}
