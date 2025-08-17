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

/// Scaled translator (N logical blocks per physical block)
base: BlockTranslator,
allocator: std.mem.Allocator,
scale_shift: u5, // How many logical blocks per physical (as power of 2)
logical_per_physical: u32,

const vtable = VTable{
    .logicalToPhysical = logicalToPhysical,
    .calculatePhysicalRange = calculatePhysicalRange,
    .planOperations = planOperations,
    .deinit = deinitTranslator,
};

pub fn create(allocator: std.mem.Allocator, physical_block_size: u32) !*Self {
    if (physical_block_size < STANDARD_BLOCK_SIZE or
        physical_block_size % STANDARD_BLOCK_SIZE != 0)
    {
        return BlockError.InvalidOperation;
    }

    const scale = physical_block_size / STANDARD_BLOCK_SIZE;
    const scale_shift = calculateShift(scale);

    const translator = try allocator.create(Self);
    errdefer allocator.destroy(translator);

    const temp_buffer = try allocator.alignedAlloc(u8, 16, physical_block_size);
    errdefer allocator.free(temp_buffer);

    translator.* = .{
        .base = .{
            .vtable = &vtable,
            .context = translator,
            .physical_block_size = physical_block_size,
            .logical_block_size = STANDARD_BLOCK_SIZE,
            .temp_buffer = temp_buffer,
        },
        .allocator = allocator,
        .scale_shift = scale_shift,
        .logical_per_physical = scale,
    };

    return translator;
}

fn calculateShift(scale: u32) u5 {
    var s = scale;
    var shift: u5 = 0;
    while (s > 1) : (shift += 1) {
        s >>= 1;
    }
    return shift;
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
        .physical_count = @truncate(last_physical - first_physical + 1),
    };
}

fn planOperations(
    ctx: *anyopaque,
    logical_start: u32,
    logical_count: u32,
    ops: []TranslationOp,
) u32 {
    const self: *Self = @ptrCast(@alignCast(ctx));

    if (ops.len == 0) return 0;

    const mask = self.logical_per_physical - 1;
    const first_physical = logical_start >> self.scale_shift;
    const last_logical = logical_start + logical_count - 1;
    const last_physical = last_logical >> self.scale_shift;
    const physical_count = last_physical - first_physical + 1;

    const first_offset = (logical_start & mask) * STANDARD_BLOCK_SIZE;
    const last_end = ((last_logical & mask) + 1) * STANDARD_BLOCK_SIZE;

    var op_count: u32 = 0;
    var buffer_offset: usize = 0;

    // First physical block (may be partial)
    if (first_offset != 0 or (physical_count == 1 and last_end != self.base.physical_block_size)) {
        if (op_count >= ops.len) return op_count;

        const copy_end = if (physical_count == 1) last_end else self.base.physical_block_size;
        const copy_size = copy_end - first_offset;

        ops[op_count] = .{
            .physical_start = first_physical,
            .physical_count = 1,
            .buffer_offset = buffer_offset,
            .buffer_size = copy_size,
            .needs_rmw = true,
            .rmw_offset = first_offset,
            .rmw_size = copy_size,
        };

        buffer_offset += copy_size;
        op_count += 1;

        if (physical_count == 1) return op_count;
    }

    // Middle physical blocks (complete)
    const middle_start = if (first_offset == 0) first_physical else first_physical + 1;
    const middle_count = if (last_end == self.base.physical_block_size)
        physical_count - @intFromBool(first_offset != 0)
    else
        physical_count - @intFromBool(first_offset != 0) - 1;

    if (middle_count > 0) {
        if (op_count >= ops.len) return op_count;

        ops[op_count] = .{
            .physical_start = middle_start,
            .physical_count = middle_count,
            .buffer_offset = buffer_offset,
            .buffer_size = middle_count * self.base.physical_block_size,
            .needs_rmw = false,
            .rmw_offset = 0,
            .rmw_size = 0,
        };

        buffer_offset += middle_count * self.base.physical_block_size;
        op_count += 1;
    }

    // Last physical block (may be partial)
    if (physical_count > 1 and last_end != self.base.physical_block_size and first_offset == 0) {
        if (op_count >= ops.len) return op_count;

        ops[op_count] = .{
            .physical_start = last_physical,
            .physical_count = 1,
            .buffer_offset = buffer_offset,
            .buffer_size = last_end,
            .needs_rmw = true,
            .rmw_offset = 0,
            .rmw_size = last_end,
        };

        op_count += 1;
    }

    return op_count;
}

fn deinitTranslator(ctx: *anyopaque) void {
    const self: *Self = @ptrCast(@alignCast(ctx));
    if (self.base.temp_buffer) |temp_buffer| self.allocator.free(temp_buffer);
    self.allocator.destroy(self);
}
