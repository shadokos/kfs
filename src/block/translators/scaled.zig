const std = @import("std");

const core = @import("../block.zig");
const STANDARD_BLOCK_SIZE = core.STANDARD_BLOCK_SIZE;
const BlockError = core.BlockError;
const BlockTranslator = core.translator.BlockTranslator;
const PhysicalRange = core.translator.PhysicalRange;
const TranslationOp = core.translator.TranslationOp;
const VTable = core.translator.VTable;

const Self = @This();

/// Scaled translator (N logical blocks per physical block)
base: BlockTranslator,
allocator: std.mem.Allocator,
scale_shift: u5, // How many logical blocks per physical (as power of 2)
block_per_sector: u32,

const vtable = VTable{
    .logicalToPhysical = logicalToPhysical,
    .calculatePhysicalRange = calculatePhysicalRange,
    .planOperations = planOperations,
    .deinit = destroy,
};

pub fn create(allocator: std.mem.Allocator, sector_size: u32) !*Self {
    if (sector_size < STANDARD_BLOCK_SIZE or sector_size % STANDARD_BLOCK_SIZE != 0)
        return BlockError.InvalidOperation;

    const scale = sector_size / STANDARD_BLOCK_SIZE;
    const scale_shift: u5 = @intCast(@ctz(scale));

    const translator = try allocator.create(Self);
    errdefer allocator.destroy(translator);

    const temp_buffer = try allocator.alignedAlloc(u8, .@"16", sector_size);
    errdefer allocator.free(temp_buffer);

    translator.* = .{
        .base = .{
            .vtable = &vtable,
            .context = translator,
            .sector_size = sector_size,
            .block_size = STANDARD_BLOCK_SIZE,
            .temp_buffer = temp_buffer,
        },
        .allocator = allocator,
        .scale_shift = scale_shift,
        .block_per_sector = scale,
    };

    return translator;
}

fn logicalToPhysical(ctx: *anyopaque, logical: u32) u32 {
    const self: *Self = @ptrCast(@alignCast(ctx));
    return logical >> self.scale_shift;
}

fn calculatePhysicalRange(
    ctx: *anyopaque,
    logical_start: u32,
    logical_count: u32,
) PhysicalRange {
    const self: *Self = @ptrCast(@alignCast(ctx));

    const first_physical = logical_start >> self.scale_shift;
    const last_logical = logical_start + logical_count - 1;
    const last_physical = last_logical >> self.scale_shift;

    return .{
        .physical_start = first_physical,
        .physical_count = @intCast(last_physical - first_physical + 1),
    };
}

const PlanState = struct {
    op_count: u32 = 0,
    buffer_offset: usize = 0,
};

fn planFirstBlock(
    self: *Self,
    ops: []TranslationOp,
    state: *PlanState,
    first_physical: u32,
    first_offset: usize,
    last_end: usize,
    physical_count: u32,
) bool {
    const needs_first = first_offset != 0 or (physical_count == 1 and last_end != self.base.sector_size);
    if (!needs_first) return false;

    if (state.op_count >= ops.len) return true; // signal early exit

    const copy_end = if (physical_count == 1) last_end else self.base.sector_size;
    const copy_size = copy_end - first_offset;

    ops[state.op_count] = .{
        .physical_start = first_physical,
        .physical_count = 1,
        .buffer_offset = state.buffer_offset,
        .buffer_size = copy_size,
        .needs_rmw = true,
        .rmw_offset = first_offset,
        .rmw_size = copy_size,
    };

    state.buffer_offset += copy_size;
    state.op_count += 1;
    return physical_count == 1; // true = we're done
}

fn planMiddleBlocks(
    self: *Self,
    ops: []TranslationOp,
    state: *PlanState,
    first_physical: u32,
    first_offset: usize,
    last_end: usize,
    physical_count: u32,
) void {
    const middle_start = if (first_offset == 0) first_physical else first_physical + 1;
    const middle_count = if (last_end == self.base.sector_size)
        physical_count - @intFromBool(first_offset != 0)
    else
        physical_count - @intFromBool(first_offset != 0) - 1;

    if (middle_count == 0) return;
    if (state.op_count >= ops.len) return;

    ops[state.op_count] = .{
        .physical_start = middle_start,
        .physical_count = middle_count,
        .buffer_offset = state.buffer_offset,
        .buffer_size = middle_count * self.base.sector_size,
        .needs_rmw = false,
        .rmw_offset = 0,
        .rmw_size = 0,
    };

    state.buffer_offset += middle_count * self.base.sector_size;
    state.op_count += 1;
}

fn planLastBlock(
    self: *Self,
    ops: []TranslationOp,
    state: *PlanState,
    last_physical: u32,
    last_end: usize,
    physical_count: u32,
) void {
    if (physical_count <= 1 or last_end == self.base.sector_size) return;
    if (state.op_count >= ops.len) return;

    ops[state.op_count] = .{
        .physical_start = last_physical,
        .physical_count = 1,
        .buffer_offset = state.buffer_offset,
        .buffer_size = last_end,
        .needs_rmw = true,
        .rmw_offset = 0,
        .rmw_size = last_end,
    };

    state.op_count += 1;
}

fn planOperations(
    ctx: *anyopaque,
    logical_start: u32,
    logical_count: u32,
    ops: []TranslationOp,
) u32 {
    const self: *Self = @ptrCast(@alignCast(ctx));

    if (ops.len == 0) return 0;

    const mask = self.block_per_sector - 1;
    const first_physical = logical_start >> self.scale_shift;
    const last_logical = logical_start + logical_count - 1;
    const last_physical = last_logical >> self.scale_shift;
    const physical_count = last_physical - first_physical + 1;

    const first_offset = (logical_start & mask) * STANDARD_BLOCK_SIZE;
    const last_end = ((last_logical & mask) + 1) * STANDARD_BLOCK_SIZE;

    var state = PlanState{};

    if (self.planFirstBlock(ops, &state, first_physical, first_offset, last_end, physical_count))
        return state.op_count;

    self.planMiddleBlocks(ops, &state, first_physical, first_offset, last_end, physical_count);
    self.planLastBlock(ops, &state, last_physical, last_end, physical_count);

    return state.op_count;
}

fn destroy(ctx: *anyopaque) void {
    const self: *Self = @ptrCast(@alignCast(ctx));
    if (self.base.temp_buffer) |temp_buffer| self.allocator.free(temp_buffer);
    self.allocator.destroy(self);
}
